#define main cli_main
#include "../src/g870ctl.c"
#undef main
#include <assert.h>
#include <sys/wait.h>
int main(void) {
 int pair[2];assert(socketpair(AF_UNIX,SOCK_STREAM,0,pair)==0);
 assert(service_peer_allowed(pair[0],getuid()));assert(!service_peer_allowed(pair[0],getuid()+1));
 int input[2],output[2];assert(pipe(input)==0&&pipe(output)==0);
 pid_t child=fork();assert(child>=0);
 if(!child) {
  close(pair[0]);close(input[1]);close(output[0]);dup2(input[0],STDIN_FILENO);dup2(output[1],STDOUT_FILENO);
  close(input[0]);close(output[1]);int result=service_tunnel(pair[1]);close(pair[1]);_exit(result);
 }
 close(pair[1]);close(input[0]);close(output[1]);
 const char *request="sample\nmode 2\nquit\n";assert(write_all(input[1],request,strlen(request))==0);close(input[1]);
 char received[128]={0};size_t used=0;ssize_t n;
 while((n=read(pair[0],received+used,sizeof(received)-used-1))>0)used+=(size_t)n;
 assert(!strcmp(received,request));const char *response="{\"ok\":true}\n";
 assert(write_all(pair[0],response,strlen(response))==0);shutdown(pair[0],SHUT_WR);close(pair[0]);
 memset(received,0,sizeof(received));used=0;
 while((n=read(output[0],received+used,sizeof(received)-used-1))>0)used+=(size_t)n;
 close(output[0]);assert(!strcmp(received,response));int status;waitpid(child,&status,0);assert(WIFEXITED(status)&&WEXITSTATUS(status)==0);
 puts("PASS: Unix peer UID allow/deny, bidirectional tunnel, EOF shutdown, exact command stream.");
}
