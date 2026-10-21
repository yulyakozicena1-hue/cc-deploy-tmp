#!/bin/bash
cd /opt/call-dash/app || exit 1
curl -sL -o /tmp/f.tgz "https://tmpfiles.org/dl/1792603895.275722e897c844aa/wzAiMHVtP2D5/cc-final.tar.gz" || exit 1
tar xzf /tmp/f.tgz || exit 1
bash deploy/fix-final.sh
