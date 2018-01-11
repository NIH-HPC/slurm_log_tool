#! /bin/bash

rm -f test.log
while read line; do
    echo "${line}" >> test.log
    sleep 1
done < testdata
