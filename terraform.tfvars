region="us-east-1"
internet_cidr_block="0.0.0.0/0"
private_subnet={
    private = {
      cidr_block        = "10.0.1.0/24"
      availability_zone = "us-east-1a"
    }
}
public_subnet={
    public = {
      cidr_block        = "10.0.2.0/24"
      availability_zone = "us-east-1a"
      public            = true
    }
}
authorized_ip=["88.106.83.189/32"]
instance_details={
    Bastion = {
      ami           = "ami-0889a44b331db0194"
      instance_type = "t2.micro"
      name          = "Bastion Server"
      user_data     = ""
    }
    WebServer = {
      ami           = "ami-0889a44b331db0194"
      instance_type = "t2.micro"
      name          = "Web Server"
      user_data     = "WebServerData.txt"
    }
    BackendServer = {
      ami           = "ami-0889a44b331db0194"
      instance_type = "t2.micro"
      name          = "Backend Server"
      user_data     = ""
    }
}