# n26-case-study
I have attached a terraform reference code and Below stems explain how this architecture works.
The architecture contains a VPC, Public & Private Subnets, An ALB, a RDS, A s3bucket, EC2 machine in autoscaling mode.
As per the architecture, when a requests hits the web url, it will pass through the ALB to the backend target configured - In this case back end servers will only accecpt request only from ALB SG
EC2 servers will be accessed the back end database and Back end data will only accepts the requests from EC2 SG group - RDS in private subnet
RDS - It is multi-AZ deployment mode for greate security and performance with enforced encryption at rest (Using KMS key auto roation for 1 year) & SSL/TLS in transit.
A S3 is configured to store the security logs of both Ec2 web access logs and RDS autentication failures logs.
A cloud watch log group is configured to monitor the above use cases and Will send an notificication via SNS topic.
A couple of things I could have implemented but Due to time limitation I couldnt do it i.e 1) a VPC private link to s3 bucket to not to route the traffic from public internet 2) a WAF solution to block OSWAP top 10 related attacks 3) ACL defination to restrict access to S3. 4) Cloud Trail logs to monitor API cals 5) VPC flow logs 6) Gateway load balancer 
