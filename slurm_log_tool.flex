/* vim: set ft=lex : */
/**********************************************************************************/
/*                                                                                */
/*                            PUBLIC DOMAIN NOTICE                                */
/*                     Center for Information Technology (CIT)                    */
/*                        National Institute of Health (NIH)                      */
/*                                                                                */
/*  This software/database is a "United States Government Work" under the         */
/*  terms of the United States Copyright Act.  It was written as part of          */
/*  the author's official duties as a United States Government employee and       */
/*  thus cannot be copyrighted.  This software is freely available                */
/*  to the public for use.  The Center for Information Technology, The            */
/*  National Institutes of Health, and the U.S. Government have not placed        */
/*  any restriction on its use or reproduction.                                   */
/*                                                                                */
/*  Although all reasonable efforts have been taken to ensure the accuracy        */
/*  and reliability of the software and data, CIT, NIH and the U.S.               */
/*  Government do not and cannot warrant the performance or results that          */
/*  may be obtained by using this software or data. CIT, NIH and the U.S.         */
/*  Government disclaim all warranties, express or implied, including             */
/*  warranties of performance, merchantability or fitness for any particular      */
/*  purpose.                                                                      */
/*                                                                                */
/*  Please cite the author (Wolfgang Resch) and the "NIH Biowulf Cluster" in any  */
/*  work or product based on this material.                                       */
/*                                                                                */
/**********************************************************************************/

/******** definitions ********/

%{

#include <stdio.h>
#include <stdbool.h>
#include <signal.h>
#include <unistd.h> // getopt, isatty

#include "partition.c" // gperf generated hash table for partitions

/**********************************************************************************/
/* Catch SIGINT and set a global 'stopit'. That way when interrupted,             */
/* the yylex loop will exit at the next newline and print the summary stats       */
/**********************************************************************************/
sig_atomic_t stopit = 0;
sig_atomic_t printit = 0;

void int_handler(int signo) {
    stopit++;
}

void usr1_handler(int signo) {
    printit++;
}

/**********************************************************************************/
/* variables for parsing the command line                                         */
/**********************************************************************************/

// in quiet mode the log isn't shown. Only the summary of events at the end
// also - yay more global variables
bool quiet = false;

/**********************************************************************************/
/* X-macros for the various events - short name,                                  */
/* color, and description. Cuts down on repetitive code                           */
/**********************************************************************************/
#define EVENT_TABLE \
  X(job_submit, "\033[38;5;33m",  "Submissions (job or array)") \
  X(sched_main, "\033[38;5;135m", "Jobs started by main scheduler") \
  X(sched_bf,   "\033[38;5;177m",  "Jobs started by backfill") \
  X(job_comp_ok,   "\033[38;5;28m",  "Jobs completed - OK") \
  X(job_comp_nok,   "\033[38;5;28;4m",  "Jobs completed - Not OK") \
  X(job_comp_term,   "\033[38;5;23;4m",  "Jobs completed - Terminated") \
  X(warn_proc_time, "\033[38;5;202m", "WARN: Note very large processing time") \
  X(warn_retry_size, "\033[38;5;202m", "WARN: agent retry_list size is...") \
  X(warn_rpc_rate, "\033[38;5;202m", "WARN: rpc rate limit exceeded") \
  X(err_conn_fail, "\033[38;5;250m\033[48;5;124m", "ERR : Communication connection failure") \
  X(err_send_node_msg, "\033[38;5;250m\033[48;5;124m", "ERR : send_node_msg") \
  X(err_zero_bytes, "\033[38;5;250m\033[48;5;124m", "ERR : Zero Bytes were transmitted") \
  X(err_ping_hung, "\033[38;5;250m\033[48;5;124m", "ERR : Node ping apparently hung") \
  X(err_invalid_type, "\033[38;5;250m\033[48;5;124m", "ERR : invalid type trying to be freed") \
  X(err_socket_to, "\033[38;5;250m\033[48;5;124m", "ERR : Socket timed out") \
  X(err_down, "\033[38;5;250m\033[48;5;124m", "ERR : Nodes not responding, setting DOWN") \
  X(err_low_mem, "\033[38;5;250m\033[48;5;124m", "ERR : Node .* has low real_memory size") \
  X(err_slurmdbd, "\033[38;5;250m\033[48;5;124m", "ERR : slurmdbd") \
  X(err_prolog, "\033[38;5;250m\033[48;5;124m", "ERR : prolog") \
  X(err_epilog, "\033[38;5;250m\033[48;5;124m", "ERR : epilog") \
  X(err_job_cred, "\033[38;5;250m\033[48;5;124m", "ERR : Job credential revoked") \
  X(err_mem_over, "\033[38;5;250m\033[48;5;124m", "ERR : node .* memory is overallocated") \
  X(err_node_not_resp, "\033[38;5;250m\033[48;5;124m", "ERR : nodes not responding") \
  X(err_gres_underflow, "\033[38;5;250m\033[48;5;124m", "ERR : GRES count underflow") \
  X(err_mem_underalloc, "\033[38;5;250m\033[48;5;124m", "ERR : memory is underallocated") \
  X(err_diff_slurm_conf, "\033[38;5;250m\033[48;5;124m", "ERR : slurm.conf mismatch") \
  X(err_orphan_step, "\033[38;5;250m\033[48;5;124m", "ERR : orphan step") \
  X(err_security, "\033[38;5;250m\033[48;5;124m", "ERR : security violation") \
  X(err_find_node_record, "\033[38;5;250m\033[48;5;124m", "ERR : find_node_record") \
  X(err_job_submit_lua, "\033[38;5;250m\033[48;5;124m", "ERR : job_submit/lua error")

#define X(a, b, c) a,
enum EVENT {
  EVENT_TABLE
};
#undef X

#define X(a, b, c) c,
char *event_desc[] = {
  EVENT_TABLE
};
#undef X

#define X(a, b, c) b,
char *event_col[] = {
  EVENT_TABLE
};
#undef X

#define X(a, b, c) 0,
size_t event_count[] = {
  EVENT_TABLE
};
#undef X

void event(enum EVENT e, const char *str) {
    if (!quiet) {
        printf("%s%s\033[0m", event_col[e], str);
    }
    event_count[e]++;
    struct partition *part = NULL;
    if (e == sched_main) {
        const char *partname = strrchr(str, '=');
        if (partname != NULL) {
            partname++;
            part = part_get(partname, strlen(partname));
            if (part != NULL) {
                part->main_count++;
            }
        }
        part = NULL;
    } else if (e == sched_bf) {
        const char *partname_start = strstr(str, " in ");
        const char *partname_end = strstr(str, " on ");
        if (partname_start != NULL && partname_end != NULL) {
            partname_start += 4;
            size_t partname_len = partname_end - partname_start;
            char partname[partname_len + 1];
            partname[partname_len] = '\0';
            strncpy(partname, partname_start, partname_len);
            part = part_get(partname, strlen(partname));
            if (part != NULL) {
                part->bf_count++;
            }
        }
        part = NULL;
    }
}

void print_summary(void) {
        fprintf(stderr, "\n--------------------- EVENTS ------------------------\n");
#define X(name, b, c) if (event_count[name] > 0) {\
         fprintf(stderr, "%43s  | %6zu\n", event_desc[name], event_count[name]); }
EVENT_TABLE
#undef X
        fprintf(stderr, "\n--------------------- SCHEDULED ---------------------\n");
        
        // print the per-partition scheduling events
        fprintf(stderr, "%16s | %8s | %8s\n", "Partition", "main", "backfill");
        fputs("-----------------|----------|---------\n", stderr);
        for (size_t i = PART_MIN_HASH_VALUE; i <= PART_MAX_HASH_VALUE; i++) {
            if (part_table[i].main_count > 0 || part_table[i].bf_count > 0) {
                fprintf(stderr, "%16s | %8zu | %8zu\n", 
                    part_table[i].name, 
                    part_table[i].main_count,
                    part_table[i].bf_count);
            }
        }
}

// This is obviously inefficient, but the program is intended to read
// from tail -f and the buffered input doesn't play well with that
#define YY_INPUT(buf,result,max_size) \
    { \
    int c = getchar(); \
    result = (c == EOF) ? YY_NULL : (buf[0] = c, 1); \
    }



%}

IDL    [a-zA-Z0-9_-]

%option noyywrap

%%

"sched: Allocate JobId=".*Partition={IDL}+ { event(sched_main, yytext); }
"sched/backfill: _start_job: Started JobId".*" in "{IDL}+" on "{IDL}+ { event(sched_bf, yytext); }
"job_complete: ".*"WEXITSTATUS 0"     { event(job_comp_ok, yytext); }
"job_complete: ".*WEXITSTATUS" "[1-9][0-9]*     { event(job_comp_nok, yytext); }
"job_complete: ".*WSIGTERM" "[0-9]+     { event(job_comp_term, yytext); }
"Job submit request" { event(job_submit, yytext); }

"Warning: Note very large processing time" { event(warn_proc_time, yytext); }
"slurmctld: agent retry_list size is "[0-9]+ { event(warn_retry_size, yytext); }
"RPC rate limit exceeded by uid "[0-9]+ { event(warn_rpc_rate, yytext); }

"Communication connection failure" { event(err_conn_fail, yytext); }
"error: slurm_send_node_msg" { event(err_send_node_msg, yytext); }
"error:".*"Zero Bytes were transmitted or received" { event(err_zero_bytes, yytext); }
"error: Node ping apparently hung, many nodes may be DOWN" { event(err_ping_hung, yytext); }
"error: Nodes ".*" not responding, setting DOWN" { event(err_down, yytext); }
"error: invalid type trying to be freed" { event(err_invalid_type, yytext); }
"error:".*"Socket timed out on send/recv" { event(err_socket_to, yytext); }
"error: Node ".*" has low real_memory size" { event(err_low_mem, yytext); }
"error: slurmdbd:" { event(err_slurmdbd, yytext); }
"error: Prolog" { event(err_prolog, yytext); }
"error:".*"epilog" { event(err_epilog, yytext); }
"slurmd error running".*"Job credential revoked" { event(err_job_cred, yytext); }
"error: cons_res: node ".*" memory is overallocated" { event(err_mem_over, yytext); }
"error: Nodes ".*" not responding" { event(err_node_not_resp, yytext); }
"error: gres/".*" GRES count underflow" { event(err_gres_underflow, yytext); }
"error:".*" memory is under-allocated" { event(err_mem_underalloc, yytext); }
"error: Node ".*"appears to have a different slurm.conf than the slurmctld" { event(err_diff_slurm_conf, yytext); }
"error: Orphan StepID=".* { event(err_orphan_step, yytext); }
"error: Security violation=".* { event(err_security, yytext); }
"error: _find_node_record" { event(err_find_node_record, yytext); }
"error: job_submit/lua" { event(err_job_submit_lua, yytext); }

. { if (!quiet) ECHO; }
\n {if (!quiet) ECHO; 
    if (stopit > 0) {
        return 0;
    }
    if (printit > 0) {
        printit = 0;
        print_summary();
        fputs("\n", stderr);
        sleep(3);
    } }

%%
/*** C code ***/

void usage(void) {
    fputs("SYNOPSIS\n", stderr);
    fputs("    slurm_log_tool [-qh] < input\n", stderr);
    fputs("DESCRIPTION\n", stderr);
    fputs("    Colorize and summarize slurm logs in batch\n", stderr);
    fputs("    or streaming. In streaming mode, hitting Ctrl-C\n", stderr);
    fputs("    prints out a summary of observed events before exiting.\n", stderr);
    fputs("    When receiving SIGUSR1, slurm_log_tool shows current stats\n", stderr);
    fputs("    summary, pauses for 3s, and then continues\n", stderr);
    fputs("OPTIONS\n", stderr);
    fputs("    -q   quiet mode - don't copy the log, just write a\n", stderr);
    fputs("         summary at the end\n", stderr);
    fputs("    -h   show this help message\n", stderr);
    fputs("EXAMPLE\n", stderr);
    fputs("    tail -f /var/log/slurm/ctld.log | slurm_log_tool\n", stderr);
    fputs("    tail -n 1000000 /var/log/slurm/ctld.log | slurm_log_tool -q\n", stderr);
}

int main(int argc, char **argv) {
    int opt;
    while ((opt = getopt(argc, argv, "qh")) != -1) {
        switch (opt) {
            case 'q': quiet = true; break;
            case 'h':
                usage();
                return EXIT_SUCCESS;
            default:
                usage();
                return EXIT_FAILURE;
        }
    }
    if (isatty(fileno(stdin))) {
        fprintf(stderr, "No data provided to stdin. See 'slurm_log_tool -h' for usage.\n");
        return EXIT_FAILURE;
    }

    // trap sigint. prints summary then exits.
    // Using sigaction since signal is deprecated. Ignores all
    // other signals while handling SIGINT
    struct sigaction act;
    memset(&act, 0, sizeof(struct sigaction));
    act.sa_handler = int_handler;
    sigfillset(&act.sa_mask);
    act.sa_flags = 0;
    if (sigaction(SIGINT, &act, NULL) == -1) {
        fprintf(stderr, "could not register handler for SIGINT\n");
        exit(1);
    }
    // trap sigusr1. prints summary, pause 5s, then continue; this one
    // needs to specify SA_RESTART - otherwise it won't continue a read
    // and quit instead
    struct sigaction act_usr1;
    memset(&act_usr1, 0, sizeof(struct sigaction));
    act_usr1.sa_handler = usr1_handler;
    sigfillset(&act_usr1.sa_mask);
    act_usr1.sa_flags = SA_RESTART;
    if (sigaction(SIGUSR1, &act_usr1, NULL) == -1) {
        fprintf(stderr, "could not register handler for SIGUSR1\n");
        exit(1);
    }

    yylex();
    print_summary();
    
    return EXIT_SUCCESS;
}
