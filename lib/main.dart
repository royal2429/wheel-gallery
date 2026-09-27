import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() => runApp(const WheelGalleryApp());

/// Sample photos. Swap these for your own URLs.
const List<String> kSampleImages = [
  'https://picsum.photos/id/111/1200/800',
  'https://picsum.photos/id/133/1200/800',
  'https://picsum.photos/id/183/1200/800',
  'https://picsum.photos/id/1071/1200/800',
  'https://picsum.photos/id/1072/1200/800',
];

class WheelGalleryApp extends StatelessWidget {
  const WheelGalleryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true),
      home: const GalleryPage(
        title: 'Tesla Model 3 Long Range AWD',
        caption: '22 Sep, 2026',
        images: kSampleImages,
      ),
    );
  }
}

/// Height of the photo header before it's expanded.
const double _kHeaderHeight = 273;

/// Timing of the photo growing to fill the screen and shrinking back.
const Duration _kExpandDuration = Duration(milliseconds: 350);
const Curve _kExpandCurve = Curves.easeInOutCubic;

/// Expanded view layout: a close / title bar across the top, the photo in a
/// rounded frame with its caption under it, and the thumbnail wheel near the
/// bottom, all on black.
const double _kBarHeight = 44;
const double _kExpandedImageWidthFactor = 0.9;
const double _kExpandedImageAspect = 0.8;
const double _kExpandedImageRadius = 16;
const double _kCaptionGap = 18;
const double _kCaptionHeight = 20;
const double _kWheelThumbSize = 78;
const double _kWheelItemExtent = 100;
const double _kWheelThumbRadius = 10;
const double _kWheelBottomGap = 70;

/// Radius of the cylinder the thumbnails wrap around. Sized so each neighbour
/// is turned about a quarter of the way from the one facing the viewer, enough
/// to read as a wheel without squashing the photos beside it.
const double _kWheelRadius = _kWheelItemExtent / 0.4;

/// A photo header that expands to fill the screen when tapped, with a
/// thumbnail wheel for picking photos.
class GalleryPage extends StatefulWidget {
  const GalleryPage({
    super.key,
    required this.title,
    required this.caption,
    required this.images,
  });

  final String title;
  final String caption;
  final List<String> images;

  @override
  State<GalleryPage> createState() => _GalleryPageState();
}

class _GalleryPageState extends State<GalleryPage>
    with SingleTickerProviderStateMixin {
  /// Drives the swipeable header photos.
  final PageController _pageController = PageController();

  /// Drives the thumbnail wheel in the expanded view.
  final FixedExtentScrollController _wheelController =
      FixedExtentScrollController();

  /// Runs the header between its collapsed (0) and expanded (1) layouts.
  late final AnimationController _expandController =
      AnimationController(vsync: this, duration: _kExpandDuration);

  /// Whether the photo has been expanded to fill the screen.
  bool _expanded = false;

  /// The photo currently showing.
  int _selected = 0;

  /// True while the wheel is being moved to follow the photos, so the items it
  /// passes on the way aren't taken as the viewer picking them.
  bool _syncingWheel = false;

  @override
  void dispose() {
    _pageController.dispose();
    _wheelController.dispose();
    _expandController.dispose();
    super.dispose();
  }

  /// The viewer swiped the big photo onto [index].
  void _onPageChanged(int index) {
    setState(() => _selected = index);
    _syncWheel(index);
  }

  /// Turns the wheel to [index], animated while it's on screen.
  void _syncWheel(int index) {
    if (!_wheelController.hasClients ||
        _wheelController.selectedItem == index) {
      return;
    }
    _syncingWheel = true;
    if (_expanded) {
      _wheelController
          .animateToItem(index,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic)
          .whenComplete(() => _syncingWheel = false);
    } else {
      _wheelController.jumpToItem(index);
      _syncingWheel = false;
    }
  }

  /// The viewer turned the wheel onto [index]: show that photo straight away,
  /// without sliding through the ones in between.
  void _onWheelChanged(int index) {
    if (_syncingWheel) return;
    HapticFeedback.selectionClick();
    _pageController.jumpToPage(index);
  }

  void _setExpanded(bool expanded) {
    if (expanded == _expanded) return;
    setState(() => _expanded = expanded);
    if (expanded) {
      _syncWheel(_selected);
      _expandController.forward();
    } else {
      _expandController.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    // While expanded, back shrinks the photo instead of leaving the page.
    return PopScope(
      canPop: !_expanded,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _setExpanded(false);
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Stack(children: [
          // Stand-in page content under the header.
          Positioned.fill(
            top: _kHeaderHeight,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(widget.title,
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                const Text('Tap the photo, or the expand button, to open the '
                    'full screen view with the thumbnail wheel.'),
              ],
            ),
          ),
          _header(context),
        ]),
      ),
    );
  }

  Widget _header(BuildContext context) {
    const containerColor = Color.fromRGBO(246, 246, 246, 0.3);
    final images = widget.images;
    final media = MediaQuery.of(context);
    final size = media.size;
    final layout = _ExpandedLayout(size, media.padding);
    final collapsedImageRect = Rect.fromLTWH(0, 0, size.width, _kHeaderHeight);
    const whiteText = TextStyle(color: Colors.white, fontSize: 12);

    return AnimatedBuilder(
      animation: _expandController,
      builder: (context, _) {
        final t = _kExpandCurve.transform(_expandController.value);
        // Collapsed controls are gone by halfway, expanded ones arrive after.
        final collapsedOpacity = (1 - t * 2).clamp(0.0, 1.0);
        final expandedOpacity = (t * 2 - 1).clamp(0.0, 1.0);
        final imageRect = Rect.lerp(collapsedImageRect, layout.imageRect, t)!;

        return AnnotatedRegion<SystemUiOverlayStyle>(
          value:
              t > 0.5 ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
          child: Container(
            height: lerpDouble(_kHeaderHeight, size.height, t),
            width: double.infinity,
            color: Color.lerp(Colors.grey.shade100, Colors.black, t),
            child: Stack(children: [
              Positioned.fromRect(
                rect: imageRect,
                child: ClipRRect(
                  borderRadius:
                      BorderRadius.circular(_kExpandedImageRadius * t),
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: images.length,
                    // Let a mouse drag the photos too (web and desktop).
                    scrollBehavior: ScrollConfiguration.of(context).copyWith(
                        dragDevices: PointerDeviceKind.values.toSet()),
                    onPageChanged: _onPageChanged,
                    itemBuilder: (context, index) => GestureDetector(
                      onTap: () => _setExpanded(!_expanded),
                      child: _NetworkPhoto(url: images[index]),
                    ),
                  ),
                ),
              ),
              // Back button over the collapsed photo.
              IgnorePointer(
                ignoring: collapsedOpacity == 0,
                child: Opacity(
                  opacity: collapsedOpacity,
                  child: Padding(
                    padding: EdgeInsets.only(
                        top: media.padding.top, left: 10, right: 10),
                    child: Row(children: [
                      _CircleButton(
                        icon: Icons.arrow_back,
                        onTap: () => Navigator.maybePop(context),
                      ),
                    ]),
                  ),
                ),
              ),
              // Expand button and photo counter along the bottom.
              Positioned(
                bottom: 20,
                left: 20,
                right: 20,
                child: IgnorePointer(
                  ignoring: collapsedOpacity == 0,
                  child: Opacity(
                    opacity: collapsedOpacity,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _CircleButton(
                          icon: Icons.open_in_full_rounded,
                          onTap: () => _setExpanded(true),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                              color: containerColor,
                              borderRadius: BorderRadius.circular(100)),
                          child: Text('${_selected + 1}/${images.length}',
                              style: whiteText),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // Close and title across the top.
              Positioned(
                top: media.padding.top,
                left: 0,
                right: 0,
                height: _kBarHeight,
                child: IgnorePointer(
                  ignoring: !_expanded,
                  child: Opacity(
                    opacity: expandedOpacity,
                    child: Row(children: [
                      _barButton(
                        onTap: () => _setExpanded(false),
                        child: const Icon(Icons.close_rounded,
                            color: Colors.white, size: 24),
                      ),
                      Expanded(
                        child: Text(
                          widget.title,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: whiteText.copyWith(
                              fontSize: 14, fontWeight: FontWeight.w700),
                        ),
                      ),
                      // Balances the close button so the title stays centred.
                      const SizedBox(width: 36 + 2 * 16),
                    ]),
                  ),
                ),
              ),
              // Caption under the photo.
              Positioned(
                top: layout.imageRect.bottom + _kCaptionGap,
                left: 0,
                right: 0,
                height: _kCaptionHeight,
                child: Opacity(
                  opacity: expandedOpacity,
                  child: Text(
                    widget.caption,
                    textAlign: TextAlign.center,
                    style: whiteText.copyWith(
                        fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              // Rises into place as the header fills the screen.
              Positioned(
                top: layout.wheelTop + 40 * (1 - t),
                left: 0,
                right: 0,
                height: _kWheelThumbSize,
                child: IgnorePointer(
                  ignoring: !_expanded,
                  child: Opacity(
                    opacity: expandedOpacity,
                    child: _ThumbnailWheel(
                      controller: _wheelController,
                      images: images,
                      onSelectedItemChanged: _onWheelChanged,
                    ),
                  ),
                ),
              ),
            ]),
          ),
        );
      },
    );
  }

  /// A bare icon in the expanded bar, with a comfortable tap target.
  Widget _barButton({required VoidCallback onTap, required Widget child}) =>
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 36 + 2 * 16,
          height: _kBarHeight,
          child: Center(child: child),
        ),
      );
}

/// Where things sit in the expanded view, in screen coordinates.
class _ExpandedLayout {
  _ExpandedLayout(Size size, EdgeInsets padding) {
    wheelTop =
        size.height - padding.bottom - _kWheelBottomGap - _kWheelThumbSize;

    // The photo and its caption share the space between the bar and the
    // wheel, sitting nearer the bar.
    final top = padding.top + _kBarHeight;
    final room = math.max(0.0, wheelTop - top);
    const captionBlock = _kCaptionGap + _kCaptionHeight;
    var width = size.width * _kExpandedImageWidthFactor;
    var height = width / _kExpandedImageAspect;
    final maxHeight = math.max(0.0, room - captionBlock - 16 - 40);
    if (height > maxHeight) {
      height = maxHeight;
      width = height * _kExpandedImageAspect;
    }
    final spare = room - height - captionBlock;
    imageRect = Rect.fromLTWH(
      (size.width - width) / 2,
      top + spare * 0.3,
      width,
      height,
    );
  }

  late final Rect imageRect;
  late final double wheelTop;
}

/// The photos laid round a cylinder: the one facing the viewer is the photo
/// shown above, and the rest turn away and shrink as they wrap round the
/// sides. Turn it or tap a photo to pick one.
class _ThumbnailWheel extends StatelessWidget {
  const _ThumbnailWheel({
    required this.controller,
    required this.images,
    required this.onSelectedItemChanged,
  });

  final FixedExtentScrollController controller;
  final List<String> images;
  final ValueChanged<int> onSelectedItemChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      // Photos fade as they turn away round the far sides.
      return ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (rect) => const LinearGradient(
          colors: [
            Colors.transparent,
            Colors.white,
            Colors.white,
            Colors.transparent
          ],
          stops: [0, 0.2, 0.8, 1],
        ).createShader(rect),
        // ListWheelScrollView only turns vertically, so lay it on its side
        // and stand each photo back up.
        child: RotatedBox(
          quarterTurns: -1,
          child: ListWheelScrollView.useDelegate(
            controller: controller,
            itemExtent: _kWheelItemExtent,
            diameterRatio: 2 * _kWheelRadius / width,
            perspective: 0.0015,
            physics: const FixedExtentScrollPhysics(),
            scrollBehavior: ScrollConfiguration.of(context)
                .copyWith(dragDevices: PointerDeviceKind.values.toSet()),
            onSelectedItemChanged: onSelectedItemChanged,
            childDelegate: ListWheelChildBuilderDelegate(
              childCount: images.length,
              builder: (context, index) => RotatedBox(
                quarterTurns: 1,
                child: GestureDetector(
                  onTap: () => controller.animateToItem(index,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutCubic),
                  child: Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(_kWheelThumbRadius),
                      child: SizedBox.square(
                        dimension: _kWheelThumbSize,
                        child: _NetworkPhoto(url: images[index]),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    });
  }
}

/// A network photo that fills its box, with a plain placeholder while it
/// loads or if it fails.
class _NetworkPhoto extends StatelessWidget {
  const _NetworkPhoto({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return Image.network(
      url,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      loadingBuilder: (context, child, progress) =>
          progress == null ? child : Container(color: Colors.grey.shade300),
      errorBuilder: (context, error, stackTrace) => Container(
        color: Colors.grey.shade300,
        alignment: Alignment.center,
        child: const Icon(Icons.broken_image_outlined, color: Colors.grey),
      ),
    );
  }
}

/// A round translucent button over the collapsed photo.
class _CircleButton extends StatelessWidget {
  const _CircleButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 36,
        width: 36,
        decoration: const BoxDecoration(
            color: Color.fromRGBO(246, 246, 246, 0.3), shape: BoxShape.circle),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }
}
