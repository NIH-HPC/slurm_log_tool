
# slurm log tool

Prettyfies slurm logs either from `tail -f` or cat and counts
events.

```shell
$ tail -f /var/log/slurm/ctld.log | slurm_log_tool

<streaming log with highlights>
<CTRL-C>
--------------------- EVENTS ------------------------
                 Submissions (job or array)  |   1218
             Jobs started by main scheduler  |    996
                   Jobs started by backfill  |    718
                             Jobs completed  |   2050
       WARN: Note very large procesing time  |     73
          WARN: agent retry_list size is...  |      3
            ERR : Node ping apparently hung  |      1

--------------------- SCHEDULED ---------------------
       Partition |     main | backfill
-----------------|----------|---------
             ccr |       22 |        9
            norm |        4 |      607
           quick |        3 |        0
          ccrgpu |        1 |        0
       multinode |        0 |       18
     interactive |        4 |        0
           niddk |      962 |       84

```

If you only want counts use `-q`

```shell
$ tail -n 100000 /var/log/slurm/ctld.log | slurm_log_tool -q

--------------------- EVENTS ------------------------
                 Submissions (job or array)  |   1218
             Jobs started by main scheduler  |    996
                   Jobs started by backfill  |    718
                             Jobs completed  |   2050
       WARN: Note very large procesing time  |     73
          WARN: agent retry_list size is...  |      3
            ERR : Node ping apparently hung  |      1

--------------------- SCHEDULED ---------------------
       Partition |     main | backfill
-----------------|----------|---------
             ccr |       22 |        9
            norm |        4 |      607
           quick |        3 |        0
          ccrgpu |        1 |        0
       multinode |        0 |       18
     interactive |        4 |        0
           niddk |      962 |       84
```

Requires gperf, flex during build. A file of partitions (`partitions.txt`) in the format

```
%%
part1, 0, 0
part2, 0, 0
%%
```

can be created manually or, if slurm is available, with `make partitions.txt`
