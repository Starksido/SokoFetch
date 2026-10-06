import os

# ENVIRONMENT has no default (see app/core/config.py). Tests always run in
# development mode, whatever the local .env says.
os.environ["ENVIRONMENT"] = "development"
