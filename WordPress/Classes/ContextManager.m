/*
 * ContextManager.m
 *
 * Copyright (c) 2013 WordPress. All rights reserved.
 *
 * Licensed under GNU General Public License 2.0.
 * Some rights reserved. See license.txt
 */

#import "ContextManager.h"
#import "WordPressComApi.h"
#import "MigrateBlogsFromFiles.h"

static ContextManager *instance;

@interface ContextManager ()

@property (nonatomic, strong) NSPersistentStoreCoordinator *persistentStoreCoordinator;
@property (nonatomic, strong) NSManagedObjectModel *managedObjectModel;
@property (nonatomic, strong) NSManagedObjectContext *mainContext;
@property (nonatomic, strong) NSManagedObjectContext *backgroundContext;

@end

@implementation ContextManager

+ (instancetype)sharedInstance {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[ContextManager alloc] init];
    });
    return instance;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Contexts

- (NSManagedObjectContext *const)newDerivedContext {
    NSManagedObjectContext *derived = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
    [derived performBlockAndWait:^{
        derived.parentContext = self.mainContext;
    }];
    
    return derived;
}

- (NSManagedObjectContext *const)mainContext {
    if (_mainContext) {
        return _mainContext;
    }
    
    _mainContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
    _mainContext.parentContext = self.backgroundContext;
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(saveBackingStore) name:NSManagedObjectContextDidSaveNotification object:_mainContext];
    
    return _mainContext;
}

- (NSManagedObjectContext *const)backgroundContext {
    if (_backgroundContext) {
        return _backgroundContext;
    }
    _backgroundContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
    _backgroundContext.persistentStoreCoordinator = [self persistentStoreCoordinator];
    _backgroundContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy;
    
    return _backgroundContext;
}

- (void)saveBackingStore {
    [self.backgroundContext performBlock:^{
        DDLogInfo(@"Saving the background writer context -- persisting.");
        NSError *error;
        if (![self.backgroundContext save:&error]) {
            @throw [NSException exceptionWithName:@"Unresolved Core Data Save Error"
                                           reason:@"Unresolved Core Data Save Error"
                                         userInfo:[error userInfo]];
        }
    }];
}

#pragma mark - Context Saving and Merging

- (void)saveDerivedContext:(NSManagedObjectContext *)context {
    [self saveDerivedContext:context withCompletionBlock:nil];
}

- (void)saveDerivedContext:(NSManagedObjectContext *)context withCompletionBlock:(void (^)())completionBlock {
    [context performBlock:^{
        __block NSError *error;
        
        DDLogInfo(@"Saving a derived context %@", context);
        [context obtainPermanentIDsForObjects:context.insertedObjects.allObjects error:nil];
        if (![context save:&error]) {
            @throw [NSException exceptionWithName:@"Unresolved Core Data Save Error"
                                           reason:@"Unresolved Core Data Save Error"
                                         userInfo:[error userInfo]];
        }
        
        if (completionBlock) {
            dispatch_async(dispatch_get_main_queue(), completionBlock);
        }
        
        [self.mainContext performBlock:^{
            DDLogInfo(@"Save main context");
            if (![self.mainContext save:&error]) {
                @throw [NSException exceptionWithName:@"Unresolved Core Data Save Error"
                                               reason:@"Unresolved Core Data Save Error"
                                             userInfo:[error userInfo]];
            }
        }];
    }];
}

#pragma mark - Setup

- (NSManagedObjectModel *)managedObjectModel {
    if (_managedObjectModel) {
        return _managedObjectModel;
    }
    NSString *modelPath = [[NSBundle mainBundle] pathForResource:@"WordPress" ofType:@"momd"];
    NSURL *modelURL = [NSURL fileURLWithPath:modelPath];
    _managedObjectModel = [[NSManagedObjectModel alloc] initWithContentsOfURL:modelURL];
    return _managedObjectModel;
}

- (NSPersistentStoreCoordinator *)persistentStoreCoordinator {
    if (_persistentStoreCoordinator) {
        return _persistentStoreCoordinator;
    }
    
    NSString *documentsDirectory = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject];
    NSURL *storeURL = [NSURL fileURLWithPath:[documentsDirectory stringByAppendingPathComponent:@"WordPress.sqlite"]];
	
	// This is important for automatic version migration. Leave it here!
	NSDictionary *options = [NSDictionary dictionaryWithObjectsAndKeys:
							 [NSNumber numberWithBool:YES], NSInferMappingModelAutomaticallyOption,
							 [NSNumber numberWithBool:YES], NSMigratePersistentStoresAutomaticallyOption, nil];
	
	NSError *error = nil;
	
    // The following conditional code is meant to test the detection of mapping model for migrations
    // It should remain disabled unless you are debugging why migrations aren't run
#if FALSE
	DDLogInfo(@"Debugging migration detection");
	NSDictionary *sourceMetadata = [NSPersistentStoreCoordinator metadataForPersistentStoreOfType:NSSQLiteStoreType
																							  URL:storeURL
																							error:&error];
	if (sourceMetadata == nil) {
		DDLogInfo(@"Can't find source persistent store");
	} else {
		DDLogInfo(@"Source store: %@", sourceMetadata);
	}
	NSManagedObjectModel *destinationModel = [self managedObjectModel];
	BOOL pscCompatibile = [destinationModel
						   isConfiguration:nil
						   compatibleWithStoreMetadata:sourceMetadata];
	if (pscCompatibile) {
		DDLogInfo(@"No migration needed");
	} else {
		DDLogInfo(@"Migration needed");
	}
	NSManagedObjectModel *sourceModel = [NSManagedObjectModel mergedModelFromBundles:nil forStoreMetadata:sourceMetadata];
	if (sourceModel != nil) {
		DDLogInfo(@"source model found");
	} else {
		DDLogInfo(@"source model not found");
	}
    
	NSMigrationManager *manager = [[NSMigrationManager alloc] initWithSourceModel:sourceModel
																 destinationModel:destinationModel];
	NSMappingModel *mappingModel = [NSMappingModel mappingModelFromBundles:[NSArray arrayWithObject:[NSBundle mainBundle]]
															forSourceModel:sourceModel
														  destinationModel:destinationModel];
	if (mappingModel != nil) {
		DDLogInfo(@"mapping model found");
	} else {
		DDLogInfo(@"mapping model not found");
	}
    
	if (NO) {
		BOOL migrates = [manager migrateStoreFromURL:storeURL
												type:NSSQLiteStoreType
											 options:nil
									withMappingModel:mappingModel
									toDestinationURL:storeURL
									 destinationType:NSSQLiteStoreType
								  destinationOptions:nil
											   error:&error];
        
		if (migrates) {
			DDLogInfo(@"migration went OK");
		} else {
			DDLogInfo(@"migration failed: %@", [error localizedDescription]);
		}
	}
	
	DDLogInfo(@"End of debugging migration detection");
#endif
    _persistentStoreCoordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:[self managedObjectModel]];
    if (![_persistentStoreCoordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:storeURL options:options error:&error]) {
		DDLogError(@"Error opening the database. %@\nDeleting the file and trying again", error);
#ifdef CORE_DATA_MIGRATION_DEBUG
		// Don't delete the database on debug builds
		// Makes migration debugging less of a pain
		abort();
#endif
        
        // make a backup of the old database
        [[NSFileManager defaultManager] copyItemAtPath:storeURL.path toPath:[storeURL.path stringByAppendingString:@"~"] error:&error];
        // delete the sqlite file and try again
		[[NSFileManager defaultManager] removeItemAtPath:storeURL.path error:nil];
		if (![_persistentStoreCoordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:storeURL options:nil error:&error]) {
			DDLogError(@"Unresolved error %@, %@", error, [error userInfo]);
			abort();
		}
        
        // If everything went wrong and we lost the DB, we sign out and simulate a fresh install
        // It's equally annoying, but it's more confusing to stay logged in to the reader having lost all the blogs in the app
        [[WordPressComApi sharedApi] signOut];
    } else {
		// If there are no blogs and blogs.archive still exists, force import of blogs
		NSFileManager *fileManager = [NSFileManager defaultManager];
		NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
		NSString *currentDirectoryPath = [[paths objectAtIndex:0] stringByAppendingPathComponent:@"wordpress"];
		NSString *blogsArchiveFilePath = [currentDirectoryPath stringByAppendingPathComponent:@"blogs.archive"];
		if ([fileManager fileExistsAtPath:blogsArchiveFilePath]) {
			NSManagedObjectContext *destMOC = [[NSManagedObjectContext alloc] init];
			[destMOC setPersistentStoreCoordinator:_persistentStoreCoordinator];
            
			MigrateBlogsFromFiles *blogMigrator = [[MigrateBlogsFromFiles alloc] init];
			[blogMigrator forceBlogsMigrationInContext:destMOC error:&error];
			if (![destMOC save:&error]) {
				DDLogError(@"Error saving blogs-only migration: %@", error);
			}
			[fileManager removeItemAtPath:blogsArchiveFilePath error:&error];
		}
	}
    
    return _persistentStoreCoordinator;
}

@end