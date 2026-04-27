# ─────────────────────────────────────────────────────────────────────────────
# Dev environment — non-sensitive values only
# NEVER commit db_username / db_password here.
# Pass secrets via:
#   export TF_VAR_db_username="..."
#   export TF_VAR_db_password="..."
# Or use Atlantis secret variables configured in atlantis.yaml
# ─────────────────────────────────────────────────────────────────────────────

aws_region = "ap-south-1"

container_image = "697502032879.dkr.ecr.ap-south-1.amazonaws.com/expense-tracker:latest"
