#pragma once
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/time.h>
#include <poll.h>
#include <launch.h>
#include <errno.h>
#include <stdlib.h>
#include <limits.h>
#define G870_SERVICE_SOCKET "/var/run/g870-control.sock"

static int write_all(int fd,const void *bytes,size_t count) {
 const char *p=bytes;
 while(count) { ssize_t n=write(fd,p,count);if(n<0&&errno==EINTR)continue;if(n<=0)return -1;p+=n;count-=(size_t)n; }
 return 0;
}
static int service_peer_allowed(int fd,uid_t allowed) {
 uid_t uid;gid_t gid;
 return getpeereid(fd,&uid,&gid)==0 && uid==allowed;
}
static int service_tunnel(int fd) {
 signal(SIGPIPE,SIG_IGN);
 struct pollfd fds[2]={{STDIN_FILENO,POLLIN,0},{fd,POLLIN,0}};
 int inputOpen=1;
 for(;;) {
  int result=poll(fds,2,-1);if(result<0&&errno==EINTR)continue;if(result<0)return 1;
  if(inputOpen&&(fds[0].revents&(POLLIN|POLLHUP))) {
   char bytes[4096];ssize_t n=read(STDIN_FILENO,bytes,sizeof(bytes));
   if(n<0&&errno==EINTR)continue;
   if(n<=0){shutdown(fd,SHUT_WR);fds[0].fd=-1;inputOpen=0;}
   else if(write_all(fd,bytes,(size_t)n))return 1;
  }
  if(fds[1].revents&(POLLIN|POLLHUP|POLLERR)) {
   char bytes[4096];ssize_t n=read(fd,bytes,sizeof(bytes));
   if(n<0&&errno==EINTR)continue;
   if(n==0)return 0;if(n<0)return 1;
   if(write_all(STDOUT_FILENO,bytes,(size_t)n))return 1;
  }
  if(fds[0].revents&(POLLERR|POLLNVAL))return 1;
 }
}
static int service_connect(void) {
 int fd=socket(AF_UNIX,SOCK_STREAM,0);if(fd<0){perror("socket");return 7;}
 struct sockaddr_un address={0};address.sun_family=AF_UNIX;
 strlcpy(address.sun_path,G870_SERVICE_SOCKET,sizeof(address.sun_path));
 if(connect(fd,(struct sockaddr*)&address,sizeof(address))) { perror("Control Center service");close(fd);return 7; }
 // Only the root launchd job may serve hardware commands.
 if(!service_peer_allowed(fd,0)){fprintf(stderr,"Service peer is not root.\n");close(fd);return 7;}
 int result=service_tunnel(fd);close(fd);return result;
}
static int service_serve(const char *uidText) {
 if(geteuid()!=0){fprintf(stderr,"Service must run as root via launchd.\n");return 4;}
 char *end=NULL;errno=0;unsigned long parsed=strtoul(uidText,&end,10);
 if(errno||!uidText[0]||*end||parsed<501||parsed>UINT_MAX)return 2;
 uid_t allowed=(uid_t)parsed;
 int *fds=NULL;size_t count=0;
 if(launch_activate_socket("Control",&fds,&count)||count!=1){free(fds);fprintf(stderr,"Missing launchd socket.\n");return 7;}
 int listener=fds[0];free(fds);
 signal(SIGPIPE,SIG_IGN);
 struct sigaction handler={0};handler.sa_handler=on_signal;sigemptyset(&handler.sa_mask);
 sigaction(SIGINT,&handler,NULL);sigaction(SIGTERM,&handler,NULL);
 while(!interrupted) {
  int peer=accept(listener,NULL,NULL);
  if(peer<0){if(errno==EINTR)continue;break;}
  if(!service_peer_allowed(peer,allowed)){close(peer);continue;}
  struct timeval timeout={10,0};
  setsockopt(peer,SOL_SOCKET,SO_RCVTIMEO,&timeout,sizeof(timeout));
  setsockopt(peer,SOL_SOCKET,SO_SNDTIMEO,&timeout,sizeof(timeout));
  io_service_t service=IOServiceGetMatchingService(kIOMainPortDefault,IOServiceMatching("G870Bridge"));
  io_connect_t connection=IO_OBJECT_NULL;
  if(!service||IOServiceOpen(service,mach_task_self(),0,&connection)) {
   if(service)IOObjectRelease(service);close(peer);continue;
  }
  FILE *input=fdopen(dup(peer),"r"),*output=fdopen(dup(peer),"w");close(peer);
  if(input&&output) {
   FILE *savedIn=stdin,*savedOut=stdout;stdin=input;stdout=output;
   session(connection,service,boolean_property(service,"HardwareControlEnabled"));
   fflush(output);stdin=savedIn;stdout=savedOut;
  }
  if(input)fclose(input);if(output)fclose(output);
  IOServiceClose(connection);IOObjectRelease(service);
 }
 close(listener);return 0;
}
