resource "aws_s3_bucket" "bucket1120027788" {
  bucket = "my-tf-test-bucket1120027788"

  tags = {
    Name        = "bucket1120027788"
    Environment = "Dev"
  }
}
