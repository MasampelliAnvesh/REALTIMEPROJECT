provider "aws" {
  profile = "default"
  region  = "us-east-1"
}

# ------------------------- KEY PAIR -------------------------
resource "aws_key_pair" "key_pair" {
  key_name   = "MyKey"
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC6vt7dk2U4doMHeCxmdNGZp92WKSGzaRh555djv7Gv/ykWEQ60zOzEohs8+y0uHGVS2KsOoylSJPWfcbqTjsgH/eATIZ1S7RWJMphXrq5r4BWi6SJMiLXTOeZkyMyI2Ei76icA52ANjzGaJGp8z6k0ofZ+o/dky+85F5j8k5iCurj0rL6LTN+gEc0RVqwhvEgR57rZ8hM2Ni/Fj5mzubtxZ1SLZJr+Yw6KxiLcbuJ2lhQ6ytljcy8z4Y+VkP4LIYvHVwBV/fBoB4Cj9To4ak1Yw5T1txTXqc0HyBmkUV/bG460YKeflZlUHWPGDBvOzBY46UWedvT4MfdA3H4Q8bUnMnIDDmzqamkthrUixUcAjkMg4tnLIksYBKUYaolaOSuCNux1/qMpA1GhpDoX1kKhBIpmcf5a2jkWLIKLqQIVBwqsAshZmI5xCAxYaTBkxYKF7hxRiXkYpKpjgWvcsUZNthrSXlwv83Puf9MZESra5KblRdWzpWq2b0E/zv9K0Is= masam@anvesh"
}

# ------------------------- VPC -------------------------
resource "aws_vpc" "prod" {
  cidr_block           = "172.20.0.0/16"
  enable_dns_hostnames = true

  tags = { Name = "prod" }
}

# ------------------------- SUBNET -------------------------
resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.prod.id
  cidr_block              = "172.20.10.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = { Name = "public-subnet" }
}

# ------------------------- INTERNET GATEWAY -------------------------
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.prod.id

  tags = { Name = "prod-igw" }
}

# ------------------------- ROUTE TABLE -------------------------
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.prod.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = { Name = "public-route-table" }
}

# ------------------------- ROUTE TABLE ASSOCIATION -------------------------
resource "aws_route_table_association" "public_rt_assoc" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

# ------------------------- SECURITY GROUP - JENKINS -------------------------
resource "aws_security_group" "jenkins_sg" {
  name        = "jenkins-sg"
  vpc_id      = aws_vpc.prod.id
  description = "SG for Jenkins Server"

  ingress {
    description = "Jenkins HTTP"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Ping"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "jenkins-sg" }
}

# ------------------------- SECURITY GROUP - MyApp -------------------------
resource "aws_security_group" "myapp_sg" {
  name        = "myapp-sg"
  vpc_id      = aws_vpc.prod.id
  description = "MyApp SG"

  ingress {
    description = "MyApp Port"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "All Inbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "myapp-sg" }
}

# ------------------------- JENKINS INSTANCE -------------------------
resource "aws_instance" "jenkins" {
  ami                    = "ami-0fa3fe0fa7920f68e"
  instance_type          = "m7i-flex.large"
  subnet_id              = aws_subnet.public_subnet.id
  key_name               = aws_key_pair.key_pair.key_name
  vpc_security_group_ids = [aws_security_group.jenkins_sg.id]

  connection {
    type        = "ssh"
    host        = self.public_ip
    user        = "ec2-user"
    private_key = file("~/.ssh/id_rsa")
  }

  provisioner "remote-exec" {
    inline = [
      "sudo yum update -y",
      "sudo yum install wget git maven ansible docker -y",
      "sudo wget -O /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat-stable/jenkins.repo",
      "sudo rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key",
      "sudo yum install jenkins -y",
      "sudo systemctl enable jenkins && sudo systemctl start jenkins",
      "sudo systemctl enable docker && sudo systemctl start docker",
      "sudo usermod -aG docker ec2-user",
      "sudo usermod -aG docker jenkins",
      "sudo chmod 666 /var/run/docker.sock",
      "sudo docker run -d --name sonar -p 9000:9000 sonarqube",
      "sudo rpm -ivh https://github.com/aquasecurity/trivy/releases/download/v0.18.3/trivy_0.18.3_Linux-64bit.rpm"
    ]
  }

  tags = { Name = "Jenkins-From-Terraform" }
}

# ------------------------- MyApp INSTANCE -------------------------
resource "aws_instance" "myapp" {
  ami                    = "ami-0fa3fe0fa7920f68e"
  instance_type          = "m7i-flex.large"
  subnet_id              = aws_subnet.public_subnet.id
  key_name               = aws_key_pair.key_pair.key_name
  vpc_security_group_ids = [aws_security_group.myapp_sg.id]

  tags = { Name = "MyApp-From-Terraform" }
}
