
all: slurm_log_tool

slurm_log_tool.c: slurm_log_tool.flex
	flex -o $@ $<

slurm_log_tool: slurm_log_tool.c
	gcc -o $@ -O3 $<

clean:
	rm -f slurm_log_tool.flex slurm_log_tool
