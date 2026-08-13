resource "aws_sqs_queue" "test_queue" {
  for_each = toset(var.test_branch_ids)

  name                        = "${var.name_prefix}-${each.key}.fifo"
  fifo_queue                  = true
  content_based_deduplication = true
}
