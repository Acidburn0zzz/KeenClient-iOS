//
//  KeenClientTests.m
//  KeenClientTests
//
//  Created by Daniel Kador on 2/8/12.
//  Copyright (c) 2012 Keen Labs. All rights reserved.
//

#import "KeenClientTests.h"
#import "KeenClient.h"
#import "CJSONDeserializer.h"
#import <OCMock/OCMock.h>


@interface KeenClientTests () {}

- (NSString *) getCacheDirectory;
- (NSString *) getKeenDirectory;
- (NSString *) getEventDirectoryForCollection: (NSString *) collection;
- (NSArray *) contentsOfDirectoryForCollection: (NSString *) collection;

@end

@implementation KeenClientTests

- (void) setUp {
    [super setUp];
    
    // Set-up code here.
}

- (void) tearDown {
    // Tear-down code here.
    
    // delete all collections and their events.
    NSError *error = nil;
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if ([fileManager fileExistsAtPath:[self getKeenDirectory]]) {
        [fileManager removeItemAtPath:[self getKeenDirectory] error:&error];
        if (error) {
            STFail(@"No error should be thrown when cleaning up: %@", [error localizedDescription]);
        }
    }
    
    [super tearDown];
}

- (void) testGetClientForAuthToken {
    KeenClient *client = [KeenClient getClientForAuthToken:@"some_token"];
    STAssertNotNil(client, @"Expected getClient with non-nil token to return non-nil client.");
    
    KeenClient *client2 = [KeenClient getClientForAuthToken:@"some_token"];
    STAssertEqualObjects(client, client2, @"getClient on the same token twice should return the same instance twice.");
        
    client = [KeenClient getClientForAuthToken:nil];
    STAssertNil(client, @"Expected getClient with nil token to return nil client.");
    
    client = [KeenClient getClientForAuthToken:@"some_other_token"];
    STAssertFalse(client == client2, @"getClient on two different tokens should return two difference instances.");
}

- (void) testAddEvent {
    KeenClient *client = [KeenClient getClientForAuthToken:@"a"];
    
    // nil dict should should do nothing
    Boolean response = [client addEvent:nil ToCollection:@"foo"];
    STAssertFalse(response, @"nil dict should return NO");
    
    // nil collection should do nothing
    response = [client addEvent:[NSDictionary dictionary] ToCollection:nil];
    STAssertFalse(response, @"nil collection should return NO");
    
    // basic dict should work
    NSArray *keys = [NSArray arrayWithObjects:@"a", @"b", @"c", nil];
    NSArray *values = [NSArray arrayWithObjects:@"apple", @"bapple", @"capple", nil];
    NSDictionary *event = [NSDictionary dictionaryWithObjects:values forKeys:keys];
    response = [client addEvent:event ToCollection:@"foo"];
    STAssertTrue(response, @"an okay event should return YES");
    // now go find the file we wrote to disk
    NSArray *contents = [self contentsOfDirectoryForCollection:@"foo"];
    NSString *path = [contents objectAtIndex:0];
    NSString *fullPath = [[self getEventDirectoryForCollection:@"foo"] stringByAppendingPathComponent:path];
    NSData *data = [NSData dataWithContentsOfFile:fullPath];
    NSError *error = nil;
    NSDictionary *deserializedDict = [[CJSONDeserializer deserializer] deserialize:data error:&error];
    // make sure timestamp was added
    STAssertNotNil(deserializedDict, @"The event should have been written to disk.");
    STAssertNotNil([deserializedDict objectForKey:@"timestamp"], @"The event written to disk should have had a timestamp added: %@", deserializedDict);
    STAssertEqualObjects(@"apple", [deserializedDict objectForKey:@"a"], @"Value for key 'a' is wrong.");
    STAssertEqualObjects(@"bapple", [deserializedDict objectForKey:@"b"], @"Value for key 'b' is wrong.");
    STAssertEqualObjects(@"capple", [deserializedDict objectForKey:@"c"], @"Value for key 'c' is wrong.");
    
    // dict with NSDate should work
    keys = [NSArray arrayWithObjects:@"a", @"b", @"a_date", nil];
    values = [NSArray arrayWithObjects:@"apple", @"bapple", [NSDate date], nil];
    event = [NSDictionary dictionaryWithObjects:values forKeys:keys];
    response = [client addEvent:event ToCollection:@"foo"];
    STAssertTrue(response, @"an event with a date should return YES"); 
    
    // now there should be two files
    contents = [self contentsOfDirectoryForCollection:@"foo"];
    STAssertTrue([contents count] == 2, @"There should be two files written.");
    
    // dict with non-serializable value should do nothing
    keys = [NSArray arrayWithObjects:@"a", @"b", @"bad_key", nil];
    NSError *badValue = [[NSError alloc] init];
    values = [NSArray arrayWithObjects:@"apple", @"bapple", badValue, nil];
    event = [NSDictionary dictionaryWithObjects:values forKeys:keys];
    response = [client addEvent:event ToCollection:@"foo"];
    STAssertFalse(response, @"an event that can't be serialized should return NO");
}

- (NSData *) sendEvent: (NSData *) data OnCollection: (NSString *) collection returningResponse: (NSURLResponse **) response error: (NSError **) error {
    // for some reason without this method, testUpload has compile warnings. this should never actually be invoked.
    // pretty annoying.
    return nil;
}

- (id) uploadTestHelperWithData: (NSString *) data AndStatusCode: (NSInteger) code {
    // set up the partial mock
    KeenClient *client = [KeenClient getClientForAuthToken:@"a"];
    id mock = [OCMockObject partialMockForObject:client];
    
    // set up the response we're faking out
    NSHTTPURLResponse *response = [[[NSHTTPURLResponse alloc] initWithURL:nil statusCode:code HTTPVersion:nil headerFields:nil] autorelease];
    
    // set up the response data we're faking out
    [[[mock stub] andReturn:[data dataUsingEncoding:NSUTF8StringEncoding]] 
     sendEvent:[OCMArg any] OnCollection:[OCMArg any] returningResponse:[OCMArg setTo:response] error:[OCMArg setTo:nil]];
    
    return mock;
}

- (void) addSimpleEventAndUploadWithMock: (id) mock {
    // add an event
    [mock addEvent:[NSDictionary dictionaryWithObject:@"apple" forKey:@"a"] ToCollection:@"foo"];
    
    // and "upload" it
    [mock upload];
}

- (void) testUploadSuccess {
    id mock = [self uploadTestHelperWithData:@"" AndStatusCode:201];
    
    [self addSimpleEventAndUploadWithMock:mock];
    
    // make sure the file was deleted locally
    NSArray *contents = [self contentsOfDirectoryForCollection:@"foo"];
    STAssertTrue([contents count] == 0, @"There should be no files after a successful upload.");
}

- (void) testUploadFailedServerDown {
    id mock = [self uploadTestHelperWithData:@"" AndStatusCode:500];
    
    [self addSimpleEventAndUploadWithMock:mock];
    
    // make sure the file wasn't deleted locally
    NSArray *contents = [self contentsOfDirectoryForCollection:@"foo"];
    STAssertTrue([contents count] == 1, @"There should be one file after a failed upload.");    
}

- (void) testUploadFailedServerDownNonJsonResponse {
    id mock = [self uploadTestHelperWithData:@"bad data" AndStatusCode:500];
    
    [self addSimpleEventAndUploadWithMock:mock];
    
    // make sure the file wasnt't deleted locally
    NSArray *contents = [self contentsOfDirectoryForCollection:@"foo"];
    STAssertTrue([contents count] == 1, @"There should be one file after a failed upload.");    
}

- (void) testUploadFailedBadRequest {
    id mock = [self uploadTestHelperWithData:@"{\"error_code\": \"InvalidCollectionNameError\"}" AndStatusCode:400];
    
    [self addSimpleEventAndUploadWithMock:mock];
    
    // make sure the file was deleted locally
    NSArray *contents = [self contentsOfDirectoryForCollection:@"foo"];
    STAssertTrue([contents count] == 0, @"An invalid event should be deleted after an upload attempt.");     
}

- (void) testUploadFailedBadRequestUnknownError {
    id mock = [self uploadTestHelperWithData:@"{\"error_code\": \"UnknownError\"}" AndStatusCode:400];
    
    [self addSimpleEventAndUploadWithMock:mock];
    
    // make sure the file was deleted locally
    NSArray *contents = [self contentsOfDirectoryForCollection:@"foo"];
    STAssertTrue([contents count] == 1, @"An upload that results in an unexpected error should not delete the event.");     
}

- (void) testUploadMultipleEventsSameCollectionSuccess {
    id mock = [self uploadTestHelperWithData:@"" AndStatusCode:201];
    
    // add an event
    [mock addEvent:[NSDictionary dictionaryWithObject:@"apple" forKey:@"a"] ToCollection:@"foo"];
    [mock addEvent:[NSDictionary dictionaryWithObject:@"apple2" forKey:@"a"] ToCollection:@"foo"];
    
    // and "upload" it
    [mock upload];
    
    // make sure the file were deleted locally
    NSArray *contents = [self contentsOfDirectoryForCollection:@"foo"];
    STAssertTrue([contents count] == 0, @"There should be no files after a successful upload.");
}

- (void) testUploadMultipleEventsDifferentCollectionSuccess {
    id mock = [self uploadTestHelperWithData:@"" AndStatusCode:201];
    
    // add an event
    [mock addEvent:[NSDictionary dictionaryWithObject:@"apple" forKey:@"a"] ToCollection:@"foo"];
    [mock addEvent:[NSDictionary dictionaryWithObject:@"bapple" forKey:@"b"] ToCollection:@"bar"];
    
    // and "upload" it
    [mock upload];
    
    // make sure the files were deleted locally
    NSArray *contents = [self contentsOfDirectoryForCollection:@"foo"];
    STAssertTrue([contents count] == 0, @"There should be no files after a successful upload.");
    contents = [self contentsOfDirectoryForCollection:@"bar"];
    STAssertTrue([contents count] == 0, @"There should be no files after a successful upload.");
}

- (void) testUploadMultipleEventsSameCollectionOneFails {
}

- (void) testUploadMultipleEventsDifferentCollectionsOneFails {
}

- (NSString *) getCacheDirectory {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    return documentsDirectory;
}

- (NSString *) getKeenDirectory {
    return [[self getCacheDirectory] stringByAppendingPathComponent:@"keen"];
}

- (NSString *) getEventDirectoryForCollection: (NSString *) collection {
    return [[self getKeenDirectory] stringByAppendingPathComponent:collection];
}

- (NSArray *) contentsOfDirectoryForCollection: (NSString *) collection {
    NSFileManager *manager = [NSFileManager defaultManager];
    NSError *error = nil;
    NSArray *contents = [manager contentsOfDirectoryAtPath:[self getEventDirectoryForCollection:collection] error:&error];
    if (error) {
        STFail(@"Error when listing contents of directory for collection %@: %@", collection, [error localizedDescription]);
    }
    return contents;
}

@end
