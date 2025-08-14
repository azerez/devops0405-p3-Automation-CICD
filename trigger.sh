#!/bin/bash

# Trigger helm publish update
echo "# trigger $(date)" >> helm/flaskapp/values.yaml
git add helm/flaskapp/values.yaml
git commit -m "chore(helm): trigger helm publish"
git push origin main
