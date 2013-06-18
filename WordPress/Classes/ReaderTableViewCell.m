//
//  ReaderTableViewCell.m
//  WordPress
//
//  Created by Eric J on 5/15/13.
//  Copyright (c) 2013 WordPress. All rights reserved.
//

#import "ReaderTableViewCell.h"
#import "WPWebViewController.h"

@implementation ReaderTableViewCell

#pragma mark - Lifecycle Methods

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {

		self.cellImageView = [[UIImageView alloc] initWithFrame:CGRectMake(0.0f, 0.0f, 44.0f, 44.0f)]; // arbitrary size.
		_cellImageView.backgroundColor = [UIColor colorWithRed:192.0f/255.0f green:192.0f/255.0f blue:192.0f/255.0f alpha:1.0f];
		_cellImageView.contentMode = UIViewContentModeScaleAspectFill;
		_cellImageView.clipsToBounds = YES;
		[self.contentView addSubview:_cellImageView];
		
		self.textContentView = [[DTAttributedTextContentView alloc] initWithFrame:CGRectMake(0.0f, 0.0f, self.frame.size.width, 44.0f)];
		_textContentView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
		_textContentView.backgroundColor = [UIColor clearColor];
		_textContentView.edgeInsets = UIEdgeInsetsMake(0.0f, 10.0f, 0.0f, 10.0f);
		_textContentView.delegate = self;
		_textContentView.shouldDrawImages = NO;
		_textContentView.shouldLayoutCustomSubviews = YES;
		[self.contentView addSubview:_textContentView];
    }
	
    return self;
}


- (void)prepareForReuse {
	[super prepareForReuse];
	[_cellImageView cancelImageRequestOperation];
	_cellImageView.image = nil;
	_textContentView.attributedString = nil;
}


#pragma mark - Instance Methods

- (CGFloat)requiredRowHeightForWidth:(CGFloat)width tableStyle:(UITableViewStyle)style {
	// Subclasses should override.
	return 44.0f;
}


- (NSAttributedString *)convertHTMLToAttributedString:(NSString *)html withOptions:(NSDictionary *)options {
    NSAssert(html != nil, @"Can't convert nil to AttributedString");
	
	NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithDictionary:@{
														  DTDefaultFontFamily:@"Open Sans",
												DTDefaultLineHeightMultiplier:@0.9,
															DTDefaultFontSize:@13,
										   NSTextSizeMultiplierDocumentOption:@1.1
								 }];
	
	if(options) {
		[dict addEntriesFromDictionary:options];
	}
	
    return [[NSAttributedString alloc] initWithHTMLData:[html dataUsingEncoding:NSUTF8StringEncoding] options:dict documentAttributes:NULL];
}


- (void)handleLinkTapped:(id)sender {
	WPWebViewController *controller = [[WPWebViewController alloc] init];
	[controller setUrl:((DTLinkButton *)sender).URL];
	[[[WordPressAppDelegate sharedWordPressApplicationDelegate] panelNavigationController] pushViewController:controller
																						   fromViewController:self.parentController
																									 animated:YES];
}


#pragma mark - DTAttributedTextContentView Delegate Methods

- (UIView *)attributedTextContentView:(DTAttributedTextContentView *)attributedTextContentView viewForAttributedString:(NSAttributedString *)string frame:(CGRect)frame {
	NSDictionary *attributes = [string attributesAtIndex:0 effectiveRange:NULL];
	
	NSURL *URL = [attributes objectForKey:DTLinkAttribute];
	NSString *identifier = [attributes objectForKey:DTGUIDAttribute];
	
	DTLinkButton *button = [[DTLinkButton alloc] initWithFrame:frame];
	button.URL = URL;
	button.minimumHitSize = CGSizeMake(25, 25); // adjusts it's bounds so that button is always large enough
	button.GUID = identifier;
	
	// get image with normal link text
	UIImage *normalImage = [attributedTextContentView contentImageWithBounds:frame options:DTCoreTextLayoutFrameDrawingDefault];
	[button setImage:normalImage forState:UIControlStateNormal];
	
	// get image for highlighted link text
	UIImage *highlightImage = [attributedTextContentView contentImageWithBounds:frame options:DTCoreTextLayoutFrameDrawingDrawLinksHighlighted];
	[button setImage:highlightImage forState:UIControlStateHighlighted];
	
	// use normal push action for opening URL
	[button addTarget:self action:@selector(handleLinkTapped:) forControlEvents:UIControlEventTouchUpInside];
	
	return button;
}


@end