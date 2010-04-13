//
//  $Id$
//
//  SPXMLExporter.h
//  sequel-pro
//
//  Created by Stuart Connolly (stuconnolly.com) on October 6, 2009
//  Copyright (c) 2009 Stuart Connolly. All rights reserved.
//
//  This program is free software; you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation; either version 2 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program; if not, write to the Free Software
//  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
//
//  More info at <http://code.google.com/p/sequel-pro/>

#import <MCPKit/MCPKit.h>

#import "SPXMLExporter.h"
#import "SPArrayAdditions.h"
#import "SPStringAdditions.h"
#import "SPFileHandle.h"
#import "SPConstants.h"

@interface SPXMLExporter (PrivateAPI)

- (NSString *)_HTMLEscapeString:(NSString *)string;

@end

@implementation SPXMLExporter

@synthesize xmlDataArray;
@synthesize xmlTableName;

/**
 * Start the XML export process. This method is automatically called when an instance of this class
 * is placed on an NSOperationQueue. Do not call it directly as there is no manual multithreading.
 */
- (void)main
{
	@try {
		NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
		NSAutoreleasePool *xmlExportPool = [[NSAutoreleasePool alloc] init];
		
		NSArray *xmlRow = nil;
		NSString *dataConversionString = nil;
		MCPStreamingResult *streamingResult = nil;
		
		NSMutableArray *xmlTags = [NSMutableArray array];
		NSMutableString *xmlString = [NSMutableString string];
		NSMutableString *xmlItem = [NSMutableString string];
		
		NSUInteger xmlRowCount = 0;
		NSUInteger i, totalRows, currentRowIndex, lastProgressValue, progressBarWidth, currentPoolDataLength;
		
		// Check that we have all the required info before starting the export
		/*if ((![self xmlDatabaseHost])     || ([[self xmlDatabaseHost] isEqualToString:@""]) ||
			(![self xmlDatabaseName])     || ([[self xmlDatabaseName] isEqualToString:@""]) ||
			(![self xmlDatabaseVersion]   || ([[self xmlDatabaseName] isEqualToString:@""])))
		{
			[pool release];
			return;
		}*/
		
		// Inform the delegate that the export process is about to begin
		if (delegate && [delegate respondsToSelector:@selector(xmlExportProcessWillBegin:)]) {
			[[self delegate] performSelectorOnMainThread:@selector(xmlExportProcessWillBegin:) withObject:self waitUntilDone:NO];
		}
		
		// Mark the process as running
		[self setExportProcessIsRunning:YES];
		
		// Updating the progress bar can take >20% of processing time - store details to only update when required
		/*progressBarWidth = (NSInteger)[singleProgressBar bounds].size.width;
		lastProgressValue = 0;
		[[singleProgressBar onMainThread] setIndeterminate:NO];
		[[singleProgressBar onMainThread] setMaxValue:progressBarWidth];
		[[singleProgressBar onMainThread] setDoubleValue:0];*/
		
		// Make a streaming request for the data if the data array isn't set
		if ((![self xmlDataArray]) && [self xmlTableName]) {
			totalRows = [[[[connection queryString:[NSString stringWithFormat:@"SELECT COUNT(1) FROM %@", [[self xmlTableName] backtickQuotedString]]] fetchRowAsArray] objectAtIndex:0] integerValue];
			streamingResult = [connection streamingQueryString:[NSString stringWithFormat:@"SELECT * FROM %@", [[self xmlTableName] backtickQuotedString]] useLowMemoryBlockingStreaming:[self exportUsingLowMemoryBlockingStreaming]];
		}
		else {
			totalRows = [[self xmlDataArray] count];
		}
		
		// Set up an array of encoded field names as opening and closing tags
		xmlRow = ([self xmlDataArray]) ? [[self xmlDataArray] objectAtIndex:0] : [streamingResult fetchFieldNames];
		
		for (i = 0; i < [xmlRow count]; i++) 
		{
			[xmlTags addObject:[NSMutableArray array]];
			
			[[xmlTags objectAtIndex:i] addObject:[NSString stringWithFormat:@"\t\t<%@>", [self _HTMLEscapeString:[[xmlRow objectAtIndex:i] description]]]];
			[[xmlTags objectAtIndex:i] addObject:[NSString stringWithFormat:@"</%@>\n", [self _HTMLEscapeString:[[xmlRow objectAtIndex:i] description]]]];
		}
		
		/*if ( !silently ) {
			
			// Set the progress text
			[[singleProgressTitle onMainThread] setStringValue:NSLocalizedString(@"Exporting XML", @"text showing that the application is exporting XML")];
			[[singleProgressText onMainThread] setStringValue:NSLocalizedString(@"Writing...", @"text showing that app is writing text file")];
			
			// Open progress sheet
			[[NSApp onMainThread] beginSheet:singleProgressSheet
							  modalForWindow:tableWindow modalDelegate:self
							  didEndSelector:nil contextInfo:nil];
			[[singleProgressSheet onMainThread] makeKeyWindow];
		}*/
		
		[[self exportOutputFileHandle] writeData:[xmlString dataUsingEncoding:[self exportOutputEncoding]]];
		
		// Write an opening tag in the form of the table name
		[[self exportOutputFileHandle] writeData:[[NSString stringWithFormat:@"\t<%@>\n", [self _HTMLEscapeString:[self xmlTableName]]] dataUsingEncoding:[self exportOutputEncoding]]];
		
		// Set up the starting row, which is 0 for streaming result sets and
		// 1 for supplied arrays which include the column headers as the first row.
		currentRowIndex = 0;
		
		if ([self xmlDataArray]) currentRowIndex++;
		
		// Drop into the processing loop
		xmlExportPool = [[NSAutoreleasePool alloc] init];
		
		currentPoolDataLength = 0;
		
		while (1) 
		{
			// Check for cancellation flag
			if ([self isCancelled]) {
				if (streamingResult) {
					[connection cancelCurrentQuery];
					[streamingResult cancelResultLoad];
				}
				
				[pool release];
				return;
			}
			
			// Retrieve the next row from the supplied data, either directly from the array...
			if ([self xmlDataArray]) {
				xmlRow = NSArrayObjectAtIndex([self xmlDataArray], currentRowIndex);
			} 
			// Or by reading an appropriate row from the streaming result
			else {
				xmlRow = [streamingResult fetchNextRowAsArray];
				
				if (!xmlRow) break;
			}
			
			// Get the cell count if we don't already have it stored
			if (!xmlRowCount) xmlRowCount = [xmlRow count];
			
			// Construct the row
			[xmlString setString:@"\t<row>\n"];
			
			for (i = 0; i < xmlRowCount; i++) 
			{
				// Retrieve the contents of this tag
				if ([NSArrayObjectAtIndex(xmlRow, i) isKindOfClass:[NSData class]]) {
					dataConversionString = [[NSString alloc] initWithData:NSArrayObjectAtIndex(xmlRow, i) encoding:[self exportOutputEncoding]];
					
					if (dataConversionString == nil) {
						dataConversionString = [[NSString alloc] initWithData:NSArrayObjectAtIndex(xmlRow, i) encoding:NSASCIIStringEncoding];
					}
					
					[xmlItem setString:[NSString stringWithString:dataConversionString]];
					[dataConversionString release];
				} 
				else {
					[xmlItem setString:[NSArrayObjectAtIndex(xmlRow, i) description]];
				}
				
				// Add the opening and closing tag and the contents to the XML string
				[xmlString appendString:NSArrayObjectAtIndex(NSArrayObjectAtIndex(xmlTags, i), 0)];
				[xmlString appendString:[self _HTMLEscapeString:xmlItem]];
				[xmlString appendString:NSArrayObjectAtIndex(NSArrayObjectAtIndex(xmlTags, i), 1)];
			}
			
			[xmlString appendString:@"\t</row>\n"];
			
			// Record the total length for use with pool flushing
			currentPoolDataLength += [xmlString length];
			
			// Write the row to the filehandle
			[[self exportOutputFileHandle] writeData:[xmlString dataUsingEncoding:[self exportOutputEncoding]]];
			
			// Update the progress counter and progress bar
			currentRowIndex++;
			
			/*if (totalRows && (currentRowIndex*progressBarWidth/totalRows) > lastProgressValue) {
				[singleProgressBar setDoubleValue:(currentRowIndex*progressBarWidth/totalRows)];
				lastProgressValue = (currentRowIndex*progressBarWidth/totalRows);
			}*/
			
			// Inform the delegate that the export's progress has been updated
			if (delegate && [delegate respondsToSelector:@selector(xmlExportProcessProgressUpdated:)]) {
				[[self delegate] performSelectorOnMainThread:@selector(xmlExportProcessProgressUpdated:) withObject:self waitUntilDone:NO];
			}
			
			// If an array was supplied and we've processed all rows, break
			if ([self xmlDataArray] && totalRows == currentRowIndex) break;
			
			// Drain the autorelease pool as required to keep memory usage low
			if (currentPoolDataLength > 250000) {
				[xmlExportPool drain];
				xmlExportPool = [[NSAutoreleasePool alloc] init];
			}
		}
		
		// Write the closing tag for the table
		[[self exportOutputFileHandle] writeData:[[NSString stringWithFormat:@"\t</%@>", [self _HTMLEscapeString:[self xmlTableName]]] dataUsingEncoding:[self exportOutputEncoding]]];
				
		// Close the progress sheet if appropriate
		/*if ( !silently ) {
			[self closeAndStopProgressSheet];
		} else {
			
			// Restore the progress bar to a normal maximum
			[[singleProgressBar onMainThread] setMaxValue:100];
		}*/
		
		// Close the file
		[[self exportOutputFileHandle] closeFile];
		
		// Mark the process as not running
		[self setExportProcessIsRunning:NO];
		
		// Inform the delegate that the export process is complete
		if (delegate && [delegate respondsToSelector:@selector(xmlExportProcessComplete:)]) {
			[[self delegate] performSelectorOnMainThread:@selector(xmlExportProcessComplete:) withObject:self waitUntilDone:NO];
		}
		
		[pool release];
	}
	@catch (NSException *e) { }
}

/**
 * Escapes HTML special characters.
 */
- (NSString *)_HTMLEscapeString:(NSString *)string
{
	NSMutableString *mutableString = [NSMutableString stringWithString:string];
	
	[mutableString replaceOccurrencesOfString:@"&" withString:@"&amp;"
									  options:NSLiteralSearch
										range:NSMakeRange(0, [mutableString length])];
	
	[mutableString replaceOccurrencesOfString:@"<" withString:@"&lt;"
									  options:NSLiteralSearch
										range:NSMakeRange(0, [mutableString length])];
	
	[mutableString replaceOccurrencesOfString:@">" withString:@"&gt;"
									  options:NSLiteralSearch
										range:NSMakeRange(0, [mutableString length])];
	
	[mutableString replaceOccurrencesOfString:@"\"" withString:@"&quot;"
									  options:NSLiteralSearch
										range:NSMakeRange(0, [mutableString length])];
	
	return [NSString stringWithString:mutableString];
}

/**
 * Dealloc
 */
- (void)dealloc
{
	if (xmlDataArray) [xmlDataArray release], xmlDataArray = nil;
	if (xmlTableName) [xmlTableName release], xmlTableName = nil;
	
	[super dealloc];
}

@end
