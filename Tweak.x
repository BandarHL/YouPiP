#import <version.h>
#import "Header.h"
#import "../YouTubeHeader/GIMBindingBuilder.h"
#import "../YouTubeHeader/GPBExtensionRegistry.h"
#import "../YouTubeHeader/MLPIPController.h"
#import "../YouTubeHeader/MLDefaultPlayerViewFactory.h"
#import "../YouTubeHeader/YTBackgroundabilityPolicy.h"
#import "../YouTubeHeader/YTMainAppControlsOverlayView.h"
#import "../YouTubeHeader/YTMainAppVideoPlayerOverlayViewController.h"
#import "../YouTubeHeader/YTHotConfig.h"
#import "../YouTubeHeader/YTLocalPlaybackController.h"
#import "../YouTubeHeader/YTPlayerPIPController.h"
#import "../YouTubeHeader/YTSettingsSectionItem.h"
#import "../YouTubeHeader/YTSettingsSectionItemManager.h"
#import "../YouTubeHeader/YTIPictureInPictureRendererRoot.h"
#import "../YouTubeHeader/YTColor.h"
#import "../YouTubeHeader/QTMIcon.h"
#import "../YouTubeHeader/YTWatchController.h"
#import "../YouTubeHeader/YTNGWatchController.h"
#import "../YouTubeHeader/YTSlimVideoScrollableActionBarCellController.h"
#import "../YouTubeHeader/YTSlimVideoScrollableDetailsActionsView.h"
#import "../YouTubeHeader/YTSlimVideoDetailsActionView.h"
#import "../YouTubeHeader/YTPageStyleController.h"

@interface YTSlimVideoScrollableDetailsActionsView ()
- (YTISlimMetadataButtonSupportedRenderers *)makeNewButtonWithTitle:(NSString *)title iconType:(int)iconType browseId:(NSString *)browseId;
@end

@interface YTMainAppControlsOverlayView (YP)
@property (retain, nonatomic) YTQTMButton *pipButton;
- (void)didPressPiP:(id)arg;
- (UIImage *)pipImage;
@end

BOOL FromUser = NO;
BOOL ForceDisablePiP = NO;

extern BOOL LegacyPiP();

BOOL UsePiPButton() {
    return [[NSUserDefaults standardUserDefaults] boolForKey:PiPActivationMethodKey];
}

BOOL UseTabBarPiPButton() {
    return [[NSUserDefaults standardUserDefaults] boolForKey:PiPActivationMethod2Key];
}

BOOL NonBackgroundable() {
    return [[NSUserDefaults standardUserDefaults] boolForKey:NonBackgroundableKey];
}

// BOOL PiPStartPaused() {
//     return [[NSUserDefaults standardUserDefaults] boolForKey:PiPStartPausedKey];
// }

BOOL isPictureInPictureActive(MLPIPController *pip) {
    return [pip respondsToSelector:@selector(pictureInPictureActive)] ? [pip pictureInPictureActive] : [pip isPictureInPictureActive];
}

static NSString *PiPIconPath;
static NSString *PiPVideoPath;

static void forcePictureInPictureInternal(YTHotConfig *hotConfig, BOOL value) {
    [hotConfig mediaHotConfig].enablePictureInPicture = value;
    YTIIosMediaHotConfig *iosMediaHotConfig = [hotConfig hotConfigGroup].mediaHotConfig.iosMediaHotConfig;
    iosMediaHotConfig.enablePictureInPicture = value;
    if ([iosMediaHotConfig respondsToSelector:@selector(setEnablePipForNonBackgroundableContent:)])
        iosMediaHotConfig.enablePipForNonBackgroundableContent = value && NonBackgroundable();
    if ([iosMediaHotConfig respondsToSelector:@selector(setEnablePipForNonPremiumUsers:)])
        iosMediaHotConfig.enablePipForNonPremiumUsers = value;
}

static void forceEnablePictureInPictureInternal(YTHotConfig *hotConfig) {
    if (ForceDisablePiP && !FromUser)
        return;
    forcePictureInPictureInternal(hotConfig, YES);
}

static void activatePiPBase(YTPlayerPIPController *controller, BOOL playPiP) {
    MLPIPController *pip = [controller valueForKey:@"_pipController"];
    if ([controller respondsToSelector:@selector(maybeEnablePictureInPicture)])
        [controller maybeEnablePictureInPicture];
    else if ([controller respondsToSelector:@selector(maybeInvokePictureInPicture)])
        [controller maybeInvokePictureInPicture];
    else {
        BOOL canPiP = [controller respondsToSelector:@selector(canEnablePictureInPicture)] && [controller canEnablePictureInPicture];
        if (!canPiP)
            canPiP = [controller respondsToSelector:@selector(canInvokePictureInPicture)] && [controller canInvokePictureInPicture];
        if (canPiP) {
            if ([pip respondsToSelector:@selector(activatePiPController)])
                [pip activatePiPController];
            else
                [pip startPictureInPicture];
        }
    }
    AVPictureInPictureController *avpip = [pip valueForKey:@"_pictureInPictureController"];
    if (playPiP) {
        if ([avpip isPictureInPicturePossible])
            [avpip startPictureInPicture];
    } else if (!isPictureInPictureActive(pip)) {
        if ([pip respondsToSelector:@selector(deactivatePiPController)])
            [pip deactivatePiPController];
        else
            [avpip stopPictureInPicture];
    }
}

static void activatePiP(YTLocalPlaybackController *local, BOOL playPiP) {
    if (![local isKindOfClass:%c(YTLocalPlaybackController)])
        return;
    YTPlayerPIPController *controller = [local valueForKey:@"_playerPIPController"];
    activatePiPBase(controller, playPiP);
}

static void bootstrapPiP(YTPlayerViewController *self, BOOL playPiP) {
    YTHotConfig *hotConfig;
    @try {
        hotConfig = [self valueForKey:@"_hotConfig"];
    } @catch (id ex) {
        hotConfig = [[self gimme] instanceForType:%c(YTHotConfig)];
    }
    forceEnablePictureInPictureInternal(hotConfig);
    YTLocalPlaybackController *local = [self valueForKey:@"_playbackController"];
    activatePiP(local, playPiP);
}

#pragma mark - Video tab bar PiP Button

%hook YTIIcon

- (UIImage *)iconImageWithColor:(UIColor *)color {
    if (self.iconType == 007) {
        YTColorPalette *colorPalette = [%c(YTPageStyleController) currentColorPalette];
        UIImage *image = [%c(QTMIcon) tintImage:[UIImage imageWithContentsOfFile:PiPIconPath] color:colorPalette.textPrimary];
        if ([image respondsToSelector:@selector(imageFlippedForRightToLeftLayoutDirection)])
            image = [image imageFlippedForRightToLeftLayoutDirection];
        return image;
    } else {
        return %orig;
    }
}
%end

%hook YTSlimVideoScrollableDetailsActionsView

- (void)createActionViewsFromSupportedRenderers:(NSMutableArray *)renderers { // for old YouTube version
    if (UseTabBarPiPButton()) {
        YTISlimMetadataButtonSupportedRenderers *PiPButton = [self makeNewButtonWithTitle:@"PiP" iconType:007 browseId:@"YouPiP.pip.command"];
        if (![renderers containsObject:PiPButton]) {
            [renderers addObject:PiPButton];
        }
    }
    %orig;
}

- (void)createActionViewsFromSupportedRenderers:(NSMutableArray *)renderers withElementsContextBlock:(id)arg2 {
    if (UseTabBarPiPButton()) {
        YTISlimMetadataButtonSupportedRenderers *PiPButton = [self makeNewButtonWithTitle:@"PiP" iconType:007 browseId:@"YouPiP.pip.command"];
        if (![renderers containsObject:PiPButton]) {
            [renderers addObject:PiPButton];
        }
    }
    %orig;
}
%new
- (YTISlimMetadataButtonSupportedRenderers *)makeNewButtonWithTitle:(NSString *)title iconType:(int)iconType browseId:(NSString *)browseId {
    YTISlimMetadataButtonSupportedRenderers *supportedRenderer = [[%c(YTISlimMetadataButtonSupportedRenderers) alloc] init];
    YTISlimMetadataButtonRenderer *metadataButtonRenderer = [[%c(YTISlimMetadataButtonRenderer) alloc] init];
    YTIButtonSupportedRenderers *buttonSupportedRenderer = [[%c(YTIButtonSupportedRenderers) alloc] init];
    YTIBrowseEndpoint *endPoint = [[%c(YTIBrowseEndpoint) alloc] init];
    YTICommand *command = [[%c(YTICommand) alloc] init];
    YTIButtonRenderer *button = [[%c(YTIButtonRenderer) alloc] init];
    YTIIcon *icon = [[%c(YTIIcon) alloc] init];

    endPoint.browseId = browseId;
    [command setBrowseEndpoint:endPoint];
    [icon setIconType:iconType];
    
    [button setStyle:8]; // Opacity style
    [button setTooltip:title];
    [button setSize:1]; // Default size
    [button setIsDisabled:false];
    [button setText:[%c(YTIFormattedString) formattedStringWithString:title]];
    [button setIcon:icon];
    [button setNavigationEndpoint:command];
    
    [buttonSupportedRenderer setButtonRenderer:button];
    [metadataButtonRenderer setButton:buttonSupportedRenderer];
    [supportedRenderer setSlimMetadataButtonRenderer:metadataButtonRenderer];
    
    return supportedRenderer;
}

%end

%hook YTSlimVideoDetailsActionView

- (void)didTapButton:(id)arg1 {
    if ([self.label.attributedText.string isEqualToString:@"PiP"]) {
        YTSlimVideoScrollableActionBarCellController *_delegate = self.delegate;
        @try {
            if ([[_delegate valueForKey:@"_metadataPanelStateProvider"] isKindOfClass:%c(YTWatchController)]) {
                YTWatchController *metadataPanelStateProvider = [_delegate valueForKey:@"_metadataPanelStateProvider"];
                if ([[metadataPanelStateProvider valueForKey:@"_playerViewController"] isKindOfClass:%c(YTPlayerViewController)]) {
                    YTPlayerViewController *playerViewController = [metadataPanelStateProvider valueForKey:@"_playerViewController"];
                    FromUser = YES;
                    bootstrapPiP(playerViewController, YES);
                }
            }
        } @catch (id ex) { // for old YouTube version
            if ([[_delegate valueForKey:@"_ngwMetadataPanelStateProvider"] isKindOfClass:%c(YTNGWatchController)]) {
                YTNGWatchController *NGWMetadataPanelStateProvider = [_delegate valueForKey:@"_ngwMetadataPanelStateProvider"];
                if ([[NGWMetadataPanelStateProvider valueForKey:@"_playerViewController"] isKindOfClass:%c(YTPlayerViewController)]) {
                    YTPlayerViewController *playerViewController = [NGWMetadataPanelStateProvider valueForKey:@"_playerViewController"];
                    FromUser = YES;
                    bootstrapPiP(playerViewController, YES);
                }
            }
        }
    } else {
        %orig;
    }
}

%end

#pragma mark - Overlay PiP Button

%hook YTMainAppVideoPlayerOverlayViewController

- (void)updateTopRightButtonAvailability {
    %orig;
    YTMainAppVideoPlayerOverlayView *v = [self videoPlayerOverlayView];
    YTMainAppControlsOverlayView *c = [v valueForKey:@"_controlsOverlayView"];
    c.pipButton.hidden = !UsePiPButton();
    [c setNeedsLayout];
}

%end

static void createPiPButton(YTMainAppControlsOverlayView *self) {
    if (self) {
        CGFloat padding = [[self class] topButtonAdditionalPadding];
        UIImage *image = [self pipImage];
        self.pipButton = [self buttonWithImage:image accessibilityLabel:@"pip" verticalContentPadding:padding];
        self.pipButton.hidden = YES;
        self.pipButton.alpha = 0;
        [self.pipButton addTarget:self action:@selector(didPressPiP:) forControlEvents:64];
        @try {
            [[self valueForKey:@"_topControlsAccessibilityContainerView"] addSubview:self.pipButton];
        } @catch (id ex) {
            [self addSubview:self.pipButton];
        }
    }
}

static NSMutableArray *topControls(YTMainAppControlsOverlayView *self, NSMutableArray *controls) {
    if (UsePiPButton()) {
        // TODO: Remove this mutable copying when iSponsorBlock fixed the data type
        if (![controls respondsToSelector:@selector(insertObject:atIndex:)])
            controls = [controls mutableCopy];
        [controls insertObject:self.pipButton atIndex:0];
    }
    return controls;
}

%hook YTMainAppControlsOverlayView

%property (retain, nonatomic) YTQTMButton *pipButton;

- (id)initWithDelegate:(id)delegate {
    self = %orig;
    createPiPButton(self);
    return self;
}

- (id)initWithDelegate:(id)delegate autoplaySwitchEnabled:(BOOL)autoplaySwitchEnabled {
    self = %orig;
    createPiPButton(self);
    return self;
}

- (NSMutableArray *)topButtonControls {
    return topControls(self, %orig);
}

- (NSMutableArray *)topControls {
    return topControls(self, %orig);
}

- (void)setTopOverlayVisible:(BOOL)visible isAutonavCanceledState:(BOOL)canceledState {
    if (UsePiPButton()) {
        if (canceledState) {
            if (!self.pipButton.hidden)
                self.pipButton.alpha = 0.0;
        } else {
            if (!self.pipButton.hidden)
                self.pipButton.alpha = visible ? 1.0 : 0.0;
        }
    }
    %orig;
}

%new
- (UIImage *)pipImage {
    static UIImage *image = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        UIColor *color = [%c(YTColor) white1];
        image = [%c(QTMIcon) tintImage:[UIImage imageWithContentsOfFile:PiPIconPath] color:color];
        if ([image respondsToSelector:@selector(imageFlippedForRightToLeftLayoutDirection)])
            image = [image imageFlippedForRightToLeftLayoutDirection];
    });
    return image;
}

%new
- (void)didPressPiP:(id)arg {
    YTMainAppVideoPlayerOverlayViewController *c = [self valueForKey:@"_eventsDelegate"];
    FromUser = YES;
    bootstrapPiP([c delegate], YES);
}

%end

#pragma mark - PiP Bootstrapping

%hook YTPlayerViewController

%new
- (void)appWillResignActive:(id)arg1 {
    if (!IS_IOS_OR_NEWER(iOS_14_0) && !UsePiPButton())
        bootstrapPiP(self, YES);
}

%end

#pragma mark - PiP Support

%hook AVPictureInPictureController

+ (BOOL)isPictureInPictureSupported {
    return YES;
}

- (void)setCanStartPictureInPictureAutomaticallyFromInline:(BOOL)canStartFromInline {
    %orig(UsePiPButton() ? NO : canStartFromInline);
}

%end

%hook AVPlayerController

- (BOOL)isPictureInPictureSupported {
    return YES;
}

%end

%hook MLPIPController

- (BOOL)isPictureInPictureSupported {
    return YES;
}

%end

%hook MLDefaultPlayerViewFactory

- (MLAVPlayerLayerView *)AVPlayerViewForVideo:(MLVideo *)video playerConfig:(MLInnerTubePlayerConfig *)playerConfig {
    forceEnablePictureInPictureInternal([self valueForKey:@"_hotConfig"]);
    return %orig;
}

%end

#pragma mark - PiP Support, Backgroundable

%hook YTIHamplayerConfig

- (BOOL)enableBackgroundable {
    return YES;
}

%end

%hook YTIBackgroundOfflineSettingCategoryEntryRenderer

- (BOOL)isBackgroundEnabled {
    return YES;
}

%end

%hook YTBackgroundabilityPolicy

- (void)updateIsBackgroundableByUserSettings {
    %orig;
    [self setValue:@(YES) forKey:@"_backgroundableByUserSettings"];
}

%end

%hook YTSettingsSectionItemManager

- (YTSettingsSectionItem *)pictureInPictureSectionItem {
    forceEnablePictureInPictureInternal([self valueForKey:@"_hotConfig"]);
    return %orig;
}

- (YTSettingsSectionItem *)pictureInPictureSectionItem:(id)arg1 {
    forceEnablePictureInPictureInternal([self valueForKey:@"_hotConfig"]);
    return %orig;
}

%end

#pragma mark - Hacks

BOOL YTSingleVideo_isLivePlayback_override = NO;

%hook YTSingleVideo

- (BOOL)isLivePlayback {
    return YTSingleVideo_isLivePlayback_override ? NO : %orig;
}

%end

static YTHotConfig *getHotConfig(YTPlayerPIPController *self) {
    @try {
        return [self valueForKey:@"_hotConfig"];
    } @catch (id ex) {
        return [[self valueForKey:@"_config"] valueForKey:@"_hotConfig"];
    }
}

%hook YTPlayerPIPController

- (BOOL)canInvokePictureInPicture {
    forceEnablePictureInPictureInternal(getHotConfig(self));
    YTSingleVideo_isLivePlayback_override = YES;
    BOOL value = %orig;
    YTSingleVideo_isLivePlayback_override = NO;
    return value;
}

- (BOOL)canEnablePictureInPicture {
    forceEnablePictureInPictureInternal(getHotConfig(self));
    YTSingleVideo_isLivePlayback_override = YES;
    BOOL value = %orig;
    YTSingleVideo_isLivePlayback_override = NO;
    return value;
}

- (void)appWillResignActive:(id)arg1 {
    forcePictureInPictureInternal(getHotConfig(self), !UsePiPButton());
    ForceDisablePiP = YES;
    if (UsePiPButton())
        activatePiPBase(self, NO);
    %orig;
    ForceDisablePiP = FromUser = NO;
}

%end

%hook YTIPlayabilityStatus

- (BOOL)isPlayableInBackground {
    return YES;
}

- (BOOL)isPlayableInPictureInPicture {
    return YES;
}

- (BOOL)hasPictureInPicture {
    return YES;
}

%end

#pragma mark - PiP Support, Binding

%hook YTAppModule

- (void)configureWithBinder:(GIMBindingBuilder *)binder {
    %orig;
    [[binder bindType:%c(MLPIPController)] initializedWith:^(id a) {
        MLPIPController *pip = [%c(MLPIPController) alloc];
        if ([pip respondsToSelector:@selector(initWithPlaceholderPlayerItemResourcePath:)])
            pip = [pip initWithPlaceholderPlayerItemResourcePath:PiPVideoPath];
        else if ([pip respondsToSelector:@selector(initWithPlaceholderPlayerItem:)])
            pip = [pip initWithPlaceholderPlayerItem:[AVPlayerItem playerItemWithURL:[NSURL URLWithString:PiPVideoPath]]];
        return pip;
    }];
}

%end

%hook YTIInnertubeResourcesIosRoot

- (GPBExtensionRegistry *)extensionRegistry {
    GPBExtensionRegistry *registry = %orig;
    [registry addExtension:[%c(YTIPictureInPictureRendererRoot) pictureInPictureRenderer]];
    return registry;
}

%end

%hook GoogleGlobalExtensionRegistry

- (GPBExtensionRegistry *)extensionRegistry {
    GPBExtensionRegistry *registry = %orig;
    [registry addExtension:[%c(YTIPictureInPictureRendererRoot) pictureInPictureRenderer]];
    return registry;
}

%end

%ctor {
    NSString *tweakBundlePath = [[NSBundle mainBundle] pathForResource:@"YouPiP" ofType:@"bundle"];
    if (tweakBundlePath) {
        NSBundle *tweakBundle = [NSBundle bundleWithPath:tweakBundlePath];
        PiPVideoPath = [tweakBundle pathForResource:@"PiPPlaceholderAsset" ofType:@"mp4"];
        PiPIconPath = [tweakBundle pathForResource:@"yt-pip-overlay" ofType:@"png"];
    } else {
        PiPVideoPath = @"/Library/Application Support/YouPiP.bundle/PiPPlaceholderAsset.mp4";
        PiPIconPath = @"/Library/Application Support/YouPiP.bundle/yt-pip-overlay.png";
    }
    %init;
}
