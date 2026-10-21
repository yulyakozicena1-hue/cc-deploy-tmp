#!/bin/bash
cd /opt/call-dash/app || exit 1
curl -sL -o /tmp/f.tgz "https://tmpfiles.org/dl/1792604896.326fc4fe247f25b5/w3AtexfHun3y/cc-final.tar.gz" || exit 1
tar xzf /tmp/f.tgz || exit 1
bash deploy/fix-final.sh
