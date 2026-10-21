#!/bin/bash
cd /opt/call-dash/app || exit 1
curl -sL -o /tmp/f.tgz "https://tmpfiles.org/dl/1792604937.54463805de2c1eed/wBA6M0L95HKQ/cc-final.tar.gz" || exit 1
tar xzf /tmp/f.tgz || exit 1
bash deploy/fix-final.sh
