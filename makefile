BINDIR := /usr/local/sbin

CFLAGS := -std=gnu99 -Wall -Wextra -pedantic -Wshadow -Wpointer-arith
CFLAGS += -Wcast-qual -O3


all: slurm_log_tool

slurm_log_tool.c: slurm_log_tool.flex
	flex --full -o $@ $<

partition.c: partition.gperf
	gperf $< > $@


slurm_log_tool: slurm_log_tool.c partition.c
	# partition.c is included in slurm_log_tool.c
	gcc -o $@ $(CFLAGS) $<

install: slurm_log_tool
	cp $< $(BINDIR)

clean:
	rm -f slurm_log_tool.c slurm_log_tool partition.c
