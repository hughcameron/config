#!/usr/bin/env bash
# Released under MIT License

# Copyright (c) 2020 Samuel Prevost.

# Permission is hereby granted, free of charge, to any person obtaining a copy of this 
# software and associated documentation files (the "Software"), to deal in the Software 
# without restriction, including without limitation the rights to use, copy, modify, merge, 
# publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons 
# to whom the Software is furnished to do so, subject to the following conditions:
# The above copyright notice and this permission notice shall be included in all copies or 
# substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, 
# INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR 
# PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE 
# FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR 
# OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER 
# DEALINGS IN THE SOFTWARE.


tlds=(com)

if [ "$#" -lt 1 ] || [[ $1 == *"."* ]]; then
    echo "Usage $0 nametotest [${tlds[*]}...]"
    exit 1
fi

BRed='\033[1;31m'         # Red
BGreen='\033[1;32m'       # Green
Color_Off='\033[0m'       # Text Reset

name=$1
shift
if [ "$#" -ne 0 ]; then
    tlds=("$@")
fi
echo -e "Checking\t$name"
echo -e "against \t${tlds[*]}"
echo "#####################################################"

whois_check() {
    # usage: whois_check google.com
    # 0: taken
    # 1: free
    whois "$1" | tr '[:upper:]' '[:lower:]' | grep -c "date:" > /dev/null 2>&1 || \
    whois "$1" | tr '[:upper:]' '[:lower:]' | grep -c "date :" > /dev/null 2>&1
}

dig_check() {
    # usage: dig_check google.com
    # 0: taken
    # 1: free
    dig "$fqdn" | grep -c 'ANSWER SECTION' > /dev/null 2>&1
}


for tld in "${tlds[@]}"; do
    fqdn="${name}.${tld}"
    echo -ne "${fqdn}\t"
    if dig_check "$fqdn" || whois_check "$fqdn"; then
        echo -e "${BRed}TAKEN"
    else
        echo -e "${BGreen}FREE"
    fi
    echo -ne "$Color_Off"
done
