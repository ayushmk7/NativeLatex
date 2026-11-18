// Renders a built app's icon through IconServices for light/dark and default/clear, without changing
// the system appearance or icon style. Static renders flatten Clear onto the system's neutral glass
// (Apple's own icons do the same); the Dock adds live backdrop translucency itself. Uses private IconServices classes: a dev check only, never ship it.
// Build: clang -fobjc-arc -framework AppKit art/tools/appearance-check.m -o /tmp/appearance-check
// Usage: appearance-check path/to/Virgule.app out-prefix   → out-prefix-{light,dark,clear-light,clear-dark}-{16,32,256,512}.png
// Prints sheet and slash RGB (0-255, the image's own components; its PNGs are written as Display P3, which review.sh converts back): sheet at 30%,30% (clear of the slash), slash at 46%,46% (inside the stroke at every size).
#import <AppKit/AppKit.h>
#import <dlfcn.h>
#import <objc/message.h>

int main(int argc, char **argv) { @autoreleasepool {
  if (argc != 3) { fprintf(stderr, "usage: %s App.app out-prefix\n", argv[0]); return 2; }
  if (!dlopen("/System/Library/PrivateFrameworks/IconServices.framework/IconServices", RTLD_NOW)) return 1;
  id icon = ((id (*)(id, SEL, id))objc_msgSend)([NSClassFromString(@"ISBundleIcon") alloc],
      NSSelectorFromString(@"initWithBundleURL:"), [NSURL fileURLWithPath:@(argv[1])]);
  for (long clear = 0; clear < 2; clear++) for (NSUInteger dark = 0; dark < 2; dark++) for (int i = 0; i < 4; i++) {
    int px = (int[]){16, 32, 256, 512}[i];
    id d = ((id (*)(id, SEL, CGSize, CGFloat))objc_msgSend)([NSClassFromString(@"ISImageDescriptor") alloc],
        NSSelectorFromString(@"initWithSize:scale:"), CGSizeMake(px, px), 1);
    ((void (*)(id, SEL, NSUInteger))objc_msgSend)(d, NSSelectorFromString(@"setAppearance:"), dark);
    ((void (*)(id, SEL, long))objc_msgSend)(d, NSSelectorFromString(@"setAppearanceVariant:"), clear ? 2 : 0);  // 2 = Clear
    // Without prepare, the first request returns the generic placeholder while rendering runs async.
    ((void (*)(id, SEL, id))objc_msgSend)(icon, NSSelectorFromString(@"prepareImageForDescriptor:"), d);
    CGImageRef cg = ((CGImageRef (*)(id, SEL, id))objc_msgSend)(icon, NSSelectorFromString(@"CGImageForImageDescriptor:"), d);
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithCGImage:cg];
    const char *mode = clear ? (dark ? "clear-dark" : "clear-light") : (dark ? "dark" : "light");
    NSString *out = [NSString stringWithFormat:@"%s-%s-%d.png", argv[2], mode, px];
    [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:out atomically:YES];
    NSColor *s = [rep colorAtX:px * 30 / 100 y:px * 30 / 100];
    NSColor *m = [rep colorAtX:px * 46 / 100 y:px * 46 / 100];
    printf("%-11s %3d sheet %3.0f %3.0f %3.0f slash %3.0f %3.0f %3.0f\n", mode, px,
           s.redComponent * 255, s.greenComponent * 255, s.blueComponent * 255,
           m.redComponent * 255, m.greenComponent * 255, m.blueComponent * 255);
  }
}}
