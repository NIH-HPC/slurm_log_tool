
# slurm log tool

Prettyfies slurm logs either from `tail -f` or cat and counts
events.

```shell
$ tail -f /var/log/slurm/ctld.log | slurm_log_tool

<streaming log with highlights>
<CTRL-C>
----------------------------------------------------------------------
Jobs submitted                               :   1218
Jobs started by main scheduler               :    996
Jobs started by backfill                     :    718
Jobs completed                               :   2050
WARN: Note very large procesing time         :     73
WARN: agent retry_list size is...            :      3
ERR : Node ping apparently hung              :      1
----------------------------------------------------------------------
```

If you only want counts use `-q`

```shell
$ tail -n 100000 /var/log/slurm/ctld.log | slurm_log_tool -q
----------------------------------------------------------------------
Jobs submitted                               :   1218
Jobs started by main scheduler               :    996
Jobs started by backfill                     :    718
Jobs completed                               :   2050
WARN: Note very large procesing time         :     73
WARN: agent retry_list size is...            :      3
ERR : Node ping apparently hung              :      1
----------------------------------------------------------------------
```
