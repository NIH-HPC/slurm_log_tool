/* vim: ft=lex */
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

/**********************************************************************************/
/* Catch SIGINT and set a global 'stopit'. That way when interrupted,             */
/* the yylex loop will exit at the next newline and print the summary stats       */
/**********************************************************************************/
static volatile int stopit = false;

void intHandler(int dummy) {
    stopit = true;
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
  X(job_submit, "\033[38;5;39m",  "Jobs submitted") \
  X(sched_main, "\033[38;5;105m", "Jobs started by main scheduler") \
  X(sched_bf,   "\033[38;5;141m",  "Jobs started by backfill") \
  X(job_comp,   "\033[38;5;192m",  "Jobs completed") \
  X(warn_proc_time, "\033[38;5;202m", "WARN: Note very large procesing time") \
  X(warn_retry_size, "\033[38;5;202m", "WARN: agent retry_list size is...") \
  X(err_conn_fail, "\033[38;5;250m\033[48;5;124m", "ERR : Communication connection failure") \
  X(err_zero_bytes, "\033[38;5;250m\033[48;5;124m", "ERR : Zero Bytes were transmitted") \
  X(err_ping_hung, "\033[38;5;250m\033[48;5;124m", "ERR : Node ping apparently hung") \
  X(err_invalid_type, "\033[38;5;250m\033[48;5;124m", "ERR : invalid type trying to be freed") \
  X(err_socket_to, "\033[38;5;250m\033[48;5;124m", "ERR : Socked timed out") \
  X(err_down, "\033[38;5;250m\033[48;5;124m", "ERR : Nodes .* not responding, setting DOWN") \
  X(err_low_mem, "\033[38;5;250m\033[48;5;124m", "ERR : Node .* has low real_memory size") \
  X(err_slurmdbd, "\033[38;5;250m\033[48;5;124m", "ERR : slurmdbd") \
  X(err_prolog, "\033[38;5;250m\033[48;5;124m", "ERR : prolog") \
  X(err_epilog, "\033[38;5;250m\033[48;5;124m", "ERR : epilog") \
  X(err_job_cred, "\033[38;5;250m\033[48;5;124m", "ERR : Job credential revoked") \
  X(err_mem_over, "\033[38;5;250m\033[48;5;124m", "ERR : node .* memory is overallocated")


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
char *event_count[] = {
  EVENT_TABLE
};
#undef X


#define event(name) do { \
    if (!quiet) printf("%s%s\033[0m", event_col[name], yytext); \
    event_count[name]++; } while (0)

// This is obviously inefficient, but the program is intended to read
// from tail -f and the buffered input doesn't play well with that
#define YY_INPUT(buf,result,max_size) \
    { \
    int c = getchar(); \
    result = (c == EOF) ? YY_NULL : (buf[0] = c, 1); \
    }



%}


%option noyywrap

%%

"sched:"/" Allocate" { event(sched_main); }
"backfill:"/" Started" { event(sched_bf); }
"job_complete: "/.*(WEXIT|WTERM)     { event(job_comp); }
"Job submit request" { event(job_submit); }

"Warning: Note very large processing time" { event(warn_proc_time); }
"slurmctld: agent retry_list size is "[0-9]+ { event(warn_retry_size); }

"Communication connection failure" { event(err_conn_fail); }
"error:".*"Zero Bytes were transmitted" { event(err_zero_bytes); }
"error: Node ping apparently hung, many nodes may be DOWN" { event(err_ping_hung); }
"error: Nodes ".*" not responding, setting DOWN" { event(err_down); }
"error: invalid type trying to be freed" { event(err_invalid_type); }
"error:".*"Socket timed out on send/recv" { event(err_socket_to); }
"error: Node ".*" has low real_memory size" { event(err_low_mem); }
"error: slurmdbd:" { event(err_slurmdbd); }
"error: Prolog" { event(err_prolog); }
"error:".*"epilog" { event(err_epilog); }
"slurmd error running".*"Job credential revoked" { event(err_job_cred); }
"error: cons_res: node ".*" memory is overallocated" { event(err_mem_over); }

. { if (!quiet) ECHO; }
\n { if (!quiet) ECHO; if (stopit) return; }

%%
/*** C code ***/

void usage(void) {
    fputs("SYNOPSIS\n", stderr);
    fputs("    slurm_log_tool [-qh] < input\n", stderr);
    fputs("DESCRIPTION\n", stderr);
    fputs("    Colorize and summarize slurm logs in batch\n", stderr);
    fputs("    or streaming. In streaming mode, hitting Ctrl-C\n", stderr);
    fputs("    prints out a summary of observed events before exiting.\n", stderr);
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
        fprintf(stderr, "No data provided to stdin\n");
        return EXIT_FAILURE;
    }

    // trap sigint
    signal(SIGINT, intHandler);
    yylex();
    fprintf(stderr, "----------------------------------------------------------------------\n");
#define X(name, b, c) if (event_count[name] > 0) {\
     fprintf(stderr, "%-45s: %6i\n", event_desc[name], event_count[name]); }
EVENT_TABLE
#undef X
    fprintf(stderr, "----------------------------------------------------------------------\n");
    return EXIT_SUCCESS;
}
