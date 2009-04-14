/***************************************************************************
 *   Copyright 2005-2009 Last.fm Ltd.                                      *
 *                                                                         *
 *   This program is free software; you can redistribute it and/or modify  *
 *   it under the terms of the GNU General Public License as published by  *
 *   the Free Software Foundation; either version 2 of the License, or     *
 *   (at your option) any later version.                                   *
 *                                                                         *
 *   This program is distributed in the hope that it will be useful,       *
 *   but WITHOUT ANY WARRANTY; without even the implied warranty of        *
 *   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the         *
 *   GNU General Public License for more details.                          *
 *                                                                         *
 *   You should have received a copy of the GNU General Public License     *
 *   along with this program; if not, write to the                         *
 *   Free Software Foundation, Inc.,                                       *
 *   51 Franklin Steet, Fifth Floor, Boston, MA  02110-1301, USA.          *
 ***************************************************************************/

#include "scrobsub.h"

#include <Cocoa/Cocoa.h>

//TODO should be per application, not per machine
#define KEYCHAIN_NAME "fm.last.Audioscrobbler"

static NSString* token;
extern void(*scrobsub_callback)(int event, const char* message);


bool scrobsub_retrieve_credentials()
{
    NSString* username = [[NSUserDefaults standardUserDefaults] stringForKey:@"Username"];
    if(!username) return false;
    scrobsub_username = strdup([username UTF8String]);
    
    void* key;
    UInt32 n;
    OSStatus err = SecKeychainFindGenericPassword(NULL, //default keychain
                                                  sizeof(KEYCHAIN_NAME),
                                                  KEYCHAIN_NAME,
                                                  strlen(scrobsub_username),
                                                  scrobsub_username,
                                                  &n,
                                                  &key,
                                                  NULL);
    scrobsub_session_key = malloc(n+1);
    memcpy(scrobsub_session_key, key, n);
    scrobsub_session_key[n] = '\0';
    
    SecKeychainItemFreeContent(NULL, key);
    (void)err; //TODO
    
    return true;
} 

void scrobsub_get(char response[256], const char* url)
{
    NSStringEncoding encoding;
    NSString *output = [NSString stringWithContentsOfURL:[NSURL URLWithString:[NSString stringWithUTF8String:url]]
                                            usedEncoding:&encoding
                                                   error:nil];
    strncpy(response, [output UTF8String], 256);
}

void scrobsub_post(char response[256], const char* url, const char* post_data)
{   
    int const n = strlen(post_data);
    NSData *body = [NSData dataWithBytes:post_data length:n];    
    
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithUTF8String:url]]
                                                           cachePolicy:NSURLRequestReloadIgnoringCacheData
                                                       timeoutInterval:10];    
    [request setHTTPMethod:@"POST"];
    [request setHTTPBody:body];
    [request setValue:@"fm.last.Audioscrobbler" forHTTPHeaderField:@"User-Agent"];
    [request setValue:[[NSNumber numberWithInteger:n] stringValue] forHTTPHeaderField:@"Content-Length"];
    [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
    
    NSURLResponse* headers = NULL;
    NSError* error = NULL;
    NSData* data = [NSURLConnection sendSynchronousRequest:request returningResponse:&headers error:&error];
    
    [data getBytes:response length:256];
}

void scrobsub_auth(char out_url[110])
{
    if(token == nil){
        NSURL* url = [NSURL URLWithString:@"http://ws.audioscrobbler.com/2.0/?method=auth.gettoken&api_key=" SCROBSUB_API_KEY ];
        NSXMLDocument* xml = [[NSXMLDocument alloc] initWithContentsOfURL:url options:0 error:nil];
        token = [[[[xml rootElement] elementsForName:@"token"] lastObject] stringValue];
        [token retain];
        [xml release];
    }

    strcpy(out_url, "http://www.last.fm/api/auth/?api_key=" SCROBSUB_API_KEY "&token=");
    strcpy(&out_url[38+32+7], [token UTF8String]);
}

//TODO localise and get webservice error
//TODO error handling
bool scrobsub_finish_auth()
{
    if(!token) return false;
    if(scrobsub_session_key) return true;
    
    char sig[33];
    NSString* format = @"api_key" SCROBSUB_API_KEY "methodauth.getSessiontoken%@" SCROBSUB_SHARED_SECRET;
    scrobsub_md5(sig, [[NSString stringWithFormat:format, token] UTF8String]);
    NSURL* url = [NSURL URLWithString:[NSString stringWithFormat:@"http://ws.audioscrobbler.com/2.0/?method=auth.getSession&api_key=" SCROBSUB_API_KEY "&token=%@&api_sig=%s", token, sig]];

    NSXMLDocument* xml = [[NSXMLDocument alloc] initWithContentsOfURL:url options:0 error:nil];
    NSXMLElement* session = [[[xml rootElement] elementsForName:@"session"] lastObject];
    NSString* sk = [[[session elementsForName:@"key"] lastObject] stringValue];
    NSString* username = [[[session elementsForName:@"name"] lastObject] stringValue];
    [xml release];

    scrobsub_session_key = strdup([sk UTF8String]);
    scrobsub_username = strdup([username UTF8String]);
    
    OSStatus err = SecKeychainAddGenericPassword(NULL, //default keychain
                                                 sizeof(KEYCHAIN_NAME),
                                                 KEYCHAIN_NAME,
                                                 strlen(scrobsub_username),
                                                 scrobsub_username,
                                                 32,
                                                 scrobsub_session_key,
                                                 NULL);
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:username forKey:@"Username"];
    [defaults synchronize];

    (void)err; //TODO
    
    return true;
}
