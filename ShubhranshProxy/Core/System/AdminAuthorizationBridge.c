#include "AdminAuthorizationBridge.h"

#include <Security/Authorization.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

OSStatus SPXRunPrivilegedShell(
    AuthorizationRef authorization,
    const char *shellCommand,
    char *outputBuffer,
    size_t outputBufferSize,
    bool allowInteraction
) {
    if (shellCommand == NULL) {
        return errAuthorizationInvalidPointer;
    }

    char *argv[] = { "-c", (char *)shellCommand, NULL };
    FILE *pipe = NULL;

    AuthorizationFlags flags = kAuthorizationFlagDefaults;
    if (allowInteraction) {
        flags |= kAuthorizationFlagInteractionAllowed | kAuthorizationFlagExtendRights;
    }

    OSStatus status = AuthorizationExecuteWithPrivileges(
        authorization,
        "/bin/sh",
        flags,
        argv,
        &pipe
    );

    if (status != errAuthorizationSuccess) {
        return status;
    }

    if (outputBuffer != NULL && outputBufferSize > 0) {
        outputBuffer[0] = '\0';
        if (pipe != NULL) {
            size_t offset = 0;
            char chunk[4096];
            while (fgets(chunk, sizeof(chunk), pipe) != NULL) {
                size_t chunkLength = strlen(chunk);
                if (offset + chunkLength + 1 >= outputBufferSize) {
                    break;
                }
                memcpy(outputBuffer + offset, chunk, chunkLength);
                offset += chunkLength;
                outputBuffer[offset] = '\0';
            }
        }
    }

    if (pipe != NULL) {
        fclose(pipe);
    }

    return errAuthorizationSuccess;
}
