#Configure the AWS Provider
provider "aws" {
	profile = "snehal"
        region  = "ap-south-1"
}
resource "tls_private_key" "t2key" {
  algorithm   = "RSA"
}
resource "aws_key_pair" "gen_key" {
  key_name   = "t2key" 
  public_key = "${tls_private_key.t2key.public_key_openssh}"
}
resource "local_file" "key-file" {
  	content  = "${tls_private_key.t2key.private_key_pem}"
  	filename = "t2key.pem"
}

resource "aws_vpc" "newvpc" {
  cidr_block = "10.1.0.0/16"
  instance_tenancy = "default"
  
  tags = {
	name = "newvpc"
	}
}
resource "aws_subnet" "newsub" {
  vpc_id     = aws_vpc.newvpc.id
  availability_zone = "ap-south-1a"
  cidr_block = "10.1.0.0/24"
  map_public_ip_on_launch = true

  tags = {
    Name = "newsub"
  }
}
resource "aws_internet_gateway" "newgw" {
  vpc_id = aws_vpc.newvpc.id

  tags = {
    Name = "newgw"
  }
}
resource "aws_route_table" "newroute" {
  vpc_id = aws_vpc.newvpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.newgw.id
  }

  tags = {
    Name = "newroute"
  }
}

resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.newsub.id
  route_table_id = aws_route_table.newroute.id
}

resource "aws_security_group" "tasksecgrp" {
  name        = "tasksecgrp"
  description = "sec group for ssh and httpd"
  vpc_id      = aws_vpc.newvpc.id

    ingress {
    description = "SSH Port"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP Port"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
   ingress {
    description = "NFS"
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "tasksecgrp"
  }
}

resource "aws_instance"  "task2instance"  {
 	ami = "ami-0447a12f28fddb066" 
  	instance_type = "t2.micro"
  	key_name = "t2key"
  	security_groups = [ "${aws_security_group.tasksecgrp.id}" ]
        availability_zone = "ap-south-1a"
	subnet_id = "${aws_subnet.newsub.id}"
   tags = {
    	  Name = "terraos" 
  	}
        
	
}
//creating efs
resource "aws_efs_file_system" "newefs" {
  creation_token = "newefs"
  performance_mode = "generalPurpose"

  tags = {
    Name = "new-efs"
  }
}

resource "aws_efs_mount_target" "alpha" {
  file_system_id = aws_efs_file_system.newefs.id
  subnet_id      = aws_subnet.newsub.id
  security_groups = ["${aws_security_group.tasksecgrp.id}"]
}

resource "null_resource" "mount_efs_volume" {


	connection {
  	  type     = "ssh"
   	  user     = "ec2-user"
   	  private_key = "${tls_private_key.t2key.private_key_pem}" 
   	  host = "${aws_instance.task2instance.public_ip}"
  }

 	provisioner "remote-exec" {
    inline = [
      "sudo yum update -y",
      "sudo yum install httpd php git amazon-efs-utils nfs-utils -y",
      "sudo setenforce 0",
      "sudo systemctl restart httpd",
      "sudo systemctl enable httpd",
      "sudo echo '${aws_efs_file_system.newefs.id}:/ /var/www/html efs defaults,_netdev 0 0' >> /etc/fstab",
      "sudo mount ${aws_efs_file_system.newefs.id}:/ /var/www/html",
      "sudo rm -rf /var/www/html/*",
      "sudo git clone https://github.com/snehal3099/web3.git /var/www/html/"
	]
  }
}

resource "aws_s3_bucket" "taskbucket3095" {
  bucket = "taskbucket3095"
  acl    = "private"
 tags = {
    Namterre        = "taskbucket3095"
  }
 
}

resource "aws_s3_bucket_public_access_block" "access_to_bucket" {
  bucket = aws_s3_bucket.taskbucket3095.id

  block_public_acls   = true
  block_public_policy = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_object" "taskobject" {
  for_each		 = fileset("C:/Users/Snehal/Desktop/terraform_code/task2", "**/*.jpg")
  bucket                 = "${aws_s3_bucket.taskbucket3095.bucket}"
  key                    = "cloud.jpg"
  source                 = "C:/Users/Snehal/Desktop/terraform_code/task2/cloud.jpg"
  content_type 		 = "image/jpg"

}
locals {
	s3_origin_id = "tasks3origin"
}

resource "aws_cloudfront_origin_access_identity" "origin_access_identity" {
	comment = "taskbucket3095"
}

resource "aws_cloudfront_distribution" "s3distribution" {

  origin {
    domain_name = "${aws_s3_bucket.taskbucket3095.bucket_regional_domain_name}"
    origin_id   = "${local.s3_origin_id}"
    s3_origin_config {
      origin_access_identity = "${aws_cloudfront_origin_access_identity.origin_access_identity.cloudfront_access_identity_path}"
    }
}
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "accessforTask1"
  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "${local.s3_origin_id}"

    forwarded_values {
      query_string = false
	cookies {
        	forward = "none"
 	    }
    }
    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

// Cache behavior with precedence 0
    ordered_cache_behavior {
    path_pattern     = "/content/immutable/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD", "OPTIONS"]
    target_origin_id = "${local.s3_origin_id}"

    forwarded_values {
      query_string = false
      headers      = ["Origin"]

      cookies {
        forward = "none"
      }
    }

    min_ttl                = 0
    default_ttl            = 86400
    max_ttl                = 31536000
    compress               = true
    viewer_protocol_policy = "redirect-to-https"
  }

  # Cache behavior with precedence 1
  ordered_cache_behavior {
    path_pattern     = "/content/*"
   allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "${local.s3_origin_id}"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
    compress               = true
    viewer_protocol_policy = "redirect-to-https"
  }

  price_class = "PriceClass_200"

  restrictions {
    geo_restriction {
      restriction_type = "whitelist"
      locations        = ["IN"]
    }
  }

  tags = {
    Name = "taskdistribution"
    Environment = "production"
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
retain_on_delete = true

depends_on=[
	aws_s3_bucket.taskbucket3095
]
}