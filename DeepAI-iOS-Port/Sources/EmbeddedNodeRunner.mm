#import "EmbeddedNodeRunner.h"
#import <NodeMobile/NodeMobile.h>
#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>
#include <fcntl.h>
#include <vector>
#include <string>

@implementation EmbeddedNodeRunner
+ (int)startScript:(NSString *)script
       workspace:(NSString *)workspace
            home:(NSString *)home
         logFile:(NSString *)logFile
{
    // iOS supports one embedded Node runtime. Keep the process inside our
    // application sandbox; never attempt to launch another process.
    setenv("T3CODE_HOME", home.fileSystemRepresentation, 1);
    setenv("HOME", home.fileSystemRepresentation, 1);
    setenv("T3CODE_MODE", "web", 1);
    setenv("T3CODE_HOST", "127.0.0.1", 1);
    setenv("T3CODE_PORT", "37730", 1);
    setenv("T3CODE_NO_BROWSER", "1", 1);
    setenv("DEEPAI_IOS_EMBEDDED", "1", 1);
    setenv("NODE_OPTIONS", "--max-old-space-size=384", 1);
    NSString *cache = [home stringByAppendingPathComponent:@"node-compile-cache"];
    [[NSFileManager defaultManager] createDirectoryAtPath:cache withIntermediateDirectories:YES attributes:nil error:nil];
    setenv("NODE_COMPILE_CACHE", cache.fileSystemRepresentation, 1);
    setenv("NODE_COMPILE_CACHE_PORTABLE", "1", 1);
    chdir(workspace.fileSystemRepresentation);

    int fd = open(logFile.fileSystemRepresentation, O_WRONLY | O_CREAT | O_APPEND, 0600);
    if (fd >= 0) {
        dup2(fd, STDERR_FILENO);
        dup2(fd, STDOUT_FILENO);
        close(fd);
    }
    fprintf(stderr, "[DeepAI iOS] Starting original DeepAI Code 0.3.40 server; node platform=ios\n");
    fflush(stderr);
    std::vector<std::string> arguments = {
        "node", std::string(script.fileSystemRepresentation), "serve",
        "--host", "127.0.0.1", "--port", "37730", "--base-dir",
        std::string(home.fileSystemRepresentation), "--no-browser",
        std::string(workspace.fileSystemRepresentation)
    };
    std::vector<char *> argv;
    argv.reserve(arguments.size() + 1);
    for (std::string &argument : arguments) argv.push_back(argument.data());
    argv.push_back(nullptr);
    int status = node_start((int)arguments.size(), argv.data());
    fprintf(stderr, "[DeepAI iOS] Original Node server exited: %d\n", status);
    fflush(stderr);
    return status;
}
@end
