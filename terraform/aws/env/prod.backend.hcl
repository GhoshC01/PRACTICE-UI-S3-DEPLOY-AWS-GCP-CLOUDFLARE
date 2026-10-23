# এই স্টেট বাকেট আগে থেকে তৈরি থাকতে হবে। এই কনফিগ বাকেট তৈরি করে না।
bucket = "my-tf-state-bucket-ui-static-page-practice"
key          = "aws/prod/terraform.tfstate"
region       = "ap-south-1"
encrypt      = true
use_lockfile = true
