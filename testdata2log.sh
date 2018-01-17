#! /bin/bash
# simulate a growing log file by appending one line
# per second to 'test.log' from 'testdata'

rm -f test.log
while read line; do
    echo "${line}" >> test.log
    sleep 1
done < testdata
