//
// Created by Nickolay Sheika on 4/25/16.
//

import Foundation
import UIKit
import QuartzCore


public protocol APKenBurnsViewDataSource: class {
    /*
        Main data source method. Data source should provide next image.
        If no image provided (data source returns nil) then previous image will be used one more time.
    */
    func nextImageForKenBurnsView(kenBurnsView: APKenBurnsView) -> UIImage?
}


public protocol APKenBurnsViewDelegate: class {

    /*
        Called when transition starts from one image to another
    */
    func kenBurnsViewDidStartTransition(kenBurnsView: APKenBurnsView, toImage: UIImage)

    /*
        Called when transition from one image to another is finished
    */
    func kenBurnsViewDidFinishTransition(kenBurnsView: APKenBurnsView)
}


public enum APKenBurnsViewFaceRecognitionMode {
    case None         // no faces recognition, simple ken burns effect
    case Biggest      // recognizes biggest face on image, if any then transition will start or will finish (chosen randomly) in center of face rect.
    case Group        // recognizes all faces on image, if any then transition will start or will finish (chosen randomly) in center of compound rect of all faces.
}


public class APKenBurnsView: UIView {

    // MARK: - DataSource

    public weak var dataSource: APKenBurnsViewDataSource?


    // MARK: - Delegate

    public weak var delegate: APKenBurnsViewDelegate?


    // MARK: - Animation Setup

    /*
        Face recognition mode. See APKenBurnsViewFaceRecognitionMode docs for more information.
    */
    public var faceRecognitionMode: APKenBurnsViewFaceRecognitionMode = .None

    /*
        Allowed deviation of scale factor.

        Example: If scaleFactorDeviation = 0.5 then allowed scale will be from 1.0 to 1.5.
        If scaleFactorDeviation = 0.0 then allowed scale will be from 1.0 to 1.0 - fixed scale factor.
    */
    public var scaleFactorDeviation: Float = 1.0

    /*
        Animation duration of one image
    */
    public var imageAnimationDuration: Double = 10.0

    /*
        Allowed deviation of animation duration of one image

        Example: if imageAnimationDuration = 10 seconds and imageAnimationDurationDeviation = 2 seconds then
        resulting image animation duration will be from 8 to 12 seconds
    */
    public var imageAnimationDurationDeviation: Double = 0.0

    /*
        Duration of transition animation between images
    */
    public var transitionAnimationDuration: Double = 4.0

    /*
        Allowed deviation of animation duration of one image
    */
    public var transitionAnimationDurationDeviation: Double = 0.0

    /*
        If set to true then recognized faces will be shown as rectangles. Only applicable for debugging.
    */
    public var showFaceRectangles: Bool = false


    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    public required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setup()
    }


    // MARK: - Public

    public func startAnimations() {
        stopAnimations()

        animationDataSource = buildAnimationDataSource()

        firstImageView.alpha = 1.0
        secondImageView.alpha = 0.0

        stopWatch = StopWatch()

        let image = dataSource?.nextImageForKenBurnsView(self)
        startTransitionWithImage(image!, imageView: firstImageView, nextImageView: secondImageView)
    }

    public func pauseAnimations() {
        firstImageView.backupAnimations()
        secondImageView.backupAnimations()

        timer?.pause()
        layer.pauseAnimations()
    }

    public func resumeAnimations() {
        firstImageView.restoreAnimations()
        secondImageView.restoreAnimations()

        timer?.resume()
        layer.resumeAnimations()
    }

    public func stopAnimations() {
        timer?.cancel()
        layer.removeAllAnimations()
    }


    // MARK: - Private Variables

    private var firstImageView: UIImageView!
    private var secondImageView: UIImageView!

    private var animationDataSource: AnimationDataSource!
    private var facesDrawer: FacesDrawerProtocol!

    private let notificationCenter = NSNotificationCenter.defaultCenter()

    private var timer: BlockTimer?
    private var stopWatch: StopWatch!


    // MARK: - Setup

    private func setup() {
        firstImageView = buildDefaultImageView()
        secondImageView = buildDefaultImageView()
        facesDrawer = FacesDrawer()
    }


    // MARK: - Lifecycle

    public override func didMoveToSuperview() {
        guard superview == nil else {
            notificationCenter.addObserver(self,
                                           selector: #selector(applicationWillResignActive),
                                           name: UIApplicationWillResignActiveNotification,
                                           object: nil)
            notificationCenter.addObserver(self,
                                           selector: #selector(applicationDidBecomeActive),
                                           name: UIApplicationDidBecomeActiveNotification,
                                           object: nil)
            return
        }
        notificationCenter.removeObserver(self)

        // required to break timer retain cycle
        stopAnimations()
    }

    deinit {
        notificationCenter.removeObserver(self)
    }


    // MARK: - Notifications

    @objc private func applicationWillResignActive(notification: NSNotification) {
        pauseAnimations()
    }

    @objc private func applicationDidBecomeActive(notification: NSNotification) {
        resumeAnimations()
    }


    // MARK: - Timer

    private func startTimerWithDelay(delay: Double, callback: () -> ()) {
        stopTimer()

        timer = BlockTimer(interval: delay, callback: callback)
    }

    private func stopTimer() {
        timer?.cancel()
    }


    // MARK: - Private

    private func buildAnimationDataSource() -> AnimationDataSource {
        let animationDependencies = ImageAnimationDependencies(scaleFactorDeviation: scaleFactorDeviation,
                                                               imageAnimationDuration: imageAnimationDuration,
                                                               imageAnimationDurationDeviation: imageAnimationDurationDeviation)
        let animationDataSourceFactory = AnimationDataSourceFactory(animationDependencies: animationDependencies,
                                                                    faceRecognitionMode: faceRecognitionMode)
        return animationDataSourceFactory.buildAnimationDataSource()
    }

    private func startTransitionWithImage(image: UIImage, imageView: UIImageView, nextImageView: UIImageView) {
        guard isValidAnimationDurations() else {
            fatalError("Animation durations setup is invalid!")
        }

        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
            self.stopWatch.start()

            var animation = self.animationDataSource.buildAnimationForImage(image, forViewPortSize: self.bounds.size)

            dispatch_async(dispatch_get_main_queue()) {

                let animationTimeCompensation = self.stopWatch.duration
                animation = ImageAnimation(startState: animation.startState,
                                           endState: animation.endState,
                                           duration: animation.duration - animationTimeCompensation)

                imageView.image = image
                imageView.animateWithImageAnimation(animation)

                if self.showFaceRectangles {
                    self.facesDrawer.drawFacesInView(imageView, image: image)
                }

                let duration = self.buildAnimationDuration()
                let delay = animation.duration - duration / 2

                self.startTimerWithDelay(delay) {

                    self.delegate?.kenBurnsViewDidStartTransition(self, toImage: image)

                    self.animateTransitionWithDuration(duration, imageView: imageView, nextImageView: nextImageView) {
                        self.delegate?.kenBurnsViewDidFinishTransition(self)
                        self.facesDrawer.cleanUpForView(imageView)
                    }

                    var nextImage = self.dataSource?.nextImageForKenBurnsView(self)
                    if nextImage == nil {
                        nextImage = image
                    }

                    self.startTransitionWithImage(nextImage!, imageView: nextImageView, nextImageView: imageView)
                }
            }
        }
    }

    private func animateTransitionWithDuration(duration: Double, imageView: UIImageView, nextImageView: UIImageView, completion: () -> ()) {
        UIView.animateWithDuration(duration,
                                   delay: 0.0,
                                   options: UIViewAnimationOptions.CurveEaseInOut,
                                   animations: {
                                       imageView.alpha = 0.0
                                       nextImageView.alpha = 1.0
                                   },
                                   completion: {
                                       finished in

                                       completion()
                                   })
    }

    private func buildAnimationDuration() -> Double {
        var durationDeviation = 0.0
        if transitionAnimationDurationDeviation > 0.0 {
            durationDeviation = RandomGenerator().randomDouble(min: -transitionAnimationDurationDeviation,
                                                               max: transitionAnimationDurationDeviation)
        }
        let duration = transitionAnimationDuration + durationDeviation
        return duration
    }

    private func isValidAnimationDurations() -> Bool {
        return imageAnimationDuration - imageAnimationDurationDeviation -
               (transitionAnimationDuration - transitionAnimationDurationDeviation) / 2 > 0.0
    }

    private func buildDefaultImageView() -> UIImageView {
        let imageView = UIImageView(frame: bounds)
        imageView.autoresizingMask = [.FlexibleHeight, .FlexibleWidth]
        imageView.contentMode = UIViewContentMode.Center
        self.addSubview(imageView)

        return imageView
    }
}