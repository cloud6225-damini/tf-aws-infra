# tf-aws-infra
Terraform Repository
Assignment 09

# Import your certificate 

aws acm import-certificate \
  --certificate fileb:///Users/daminithorat/Downloads/demo_daminithorat.me/demo_daminithorat_me.crt \
  --private-key fileb:///Users/daminithorat/demo.daminithorat.me.key \
  --certificate-chain fileb:///Users/daminithorat/Downloads/demo_daminithorat.me/demo_daminithorat_me.ca-bundle