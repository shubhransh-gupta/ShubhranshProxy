#ifndef AdminAuthorizationBridge_h
#define AdminAuthorizationBridge_h

#include <Security/Authorization.h>
#include <stddef.h>
#include <stdbool.h>

OSStatus SPXRunPrivilegedShell(
    AuthorizationRef authorization,
    const char *shellCommand,
    char *outputBuffer,
    size_t outputBufferSize,
    bool allowInteraction
);

#endif /* AdminAuthorizationBridge_h */
