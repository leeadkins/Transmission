//
// Copyright (c) Nathan Tannar
//

#if os(iOS)

import SwiftUI
import UIKit
import Engine
import Turbocharger

@available(iOS 14.0, *)
@available(macOS, unavailable)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
class SlidePresentationController: PresentationController, UIGestureRecognizerDelegate {

    private weak var transition: SlideTransition?
    var edge: Edge = .bottom

    lazy var panGesture = UIPanGestureRecognizer(target: self, action: #selector(onPanGesture(_:)))

    private var isPanGestureActive = false
    private var translationOffset: CGPoint = .zero

    override var presentationStyle: UIModalPresentationStyle { .overFullScreen }

    func begin(transition: SlideTransition, isInteractive: Bool) {
        self.transition = transition
        transition.wantsInteractiveStart = isInteractive && isPanGestureActive
    }

    override func presentationTransitionDidEnd(_ completed: Bool) {
        super.presentationTransitionDidEnd(completed)

        if completed {
            panGesture.delegate = self
            panGesture.allowedScrollTypesMask = .all
            containerView?.addGestureRecognizer(panGesture)
        }
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        delegate?.presentationControllerShouldDismiss?(self) ?? false
    }

    @objc
    private func onPanGesture(_ gestureRecognizer: UIPanGestureRecognizer) {
        let scrollView = gestureRecognizer.view as? UIScrollView
        guard let containerView = scrollView ?? containerView else {
            return
        }

        let gestureTranslation = gestureRecognizer.translation(in: containerView)
        let offset = CGSize(
            width: gestureTranslation.x - translationOffset.x,
            height: gestureTranslation.y - translationOffset.y
        )
        let translation: CGFloat
        let percentage: CGFloat
        switch edge {
        case .top:
            if let scrollView {
                translation = max(0, scrollView.contentSize.height + scrollView.adjustedContentInset.top - scrollView.bounds.height) + offset.height
            } else {
                translation = offset.height
            }
            percentage = translation / containerView.bounds.height
        case .bottom:
            translation = offset.height
            percentage = translation / containerView.bounds.height
        case .leading:
            if let scrollView {
                translation = max(0, scrollView.contentSize.width + scrollView.adjustedContentInset.left - scrollView.bounds.width) + offset.width
            } else {
                translation = offset.width
            }
            percentage = translation / containerView.bounds.width
        case .trailing:
            translation = offset.width
            percentage = translation / containerView.bounds.width
        }

        guard isPanGestureActive else {
            let shouldBeginDismissal: Bool
            switch edge {
            case .top, .leading:
                shouldBeginDismissal = translation < 1
            case .bottom, .trailing:
                shouldBeginDismissal = translation > 1
            }
            if shouldBeginDismissal,
               !presentedViewController.isBeingDismissed,
               scrollView.map({ isAtTop(scrollView: $0) }) ?? true
            {
                #if targetEnvironment(macCatalyst)
                let canStart = true
                #else
                var views = gestureRecognizer.view.map { [$0] } ?? []
                var firstResponder: UIView?
                var index = 0
                repeat {
                    let view = views[index]
                    if view.isFirstResponder {
                        firstResponder = view
                    } else {
                        views.append(contentsOf: view.subviews)
                        index += 1
                    }
                } while index < views.count && firstResponder == nil
                let canStart = firstResponder?.resignFirstResponder() ?? true
                #endif
                if canStart, gestureRecognizerShouldBegin(gestureRecognizer) {
                    isPanGestureActive = true
                    presentedViewController.dismiss(animated: true)
                }
            }
            return
        }

        guard percentage > 0 && (edge == .bottom || edge == .trailing) ||
                percentage < 0 && (edge == .top || edge == .leading)
        else {
            transition?.cancel()
            isPanGestureActive = false
            return
        }

        switch gestureRecognizer.state {
        case .began, .changed:
            if let scrollView = scrollView {
                switch edge {
                case .top:
                    scrollView.contentOffset.y = max(-scrollView.adjustedContentInset.top, scrollView.contentSize.height + scrollView.adjustedContentInset.top - scrollView.frame.height)

                case .bottom:
                    scrollView.contentOffset.y = -scrollView.adjustedContentInset.top

                case .leading:
                    scrollView.contentOffset.x = max(-scrollView.adjustedContentInset.left, scrollView.contentSize.width + scrollView.adjustedContentInset.left - scrollView.frame.width)

                case .trailing:
                    scrollView.contentOffset.x = -scrollView.adjustedContentInset.right
                }
            }

            transition?.update(abs(percentage))

        case .ended, .cancelled:
            // Dismiss if:
            // - Drag over 50% and not moving up
            // - Large enough down vector
            let velocity: CGFloat
            switch edge {
            case .top:
                velocity = -gestureRecognizer.velocity(in: containerView).y
            case .bottom:
                velocity = gestureRecognizer.velocity(in: containerView).y
            case .leading:
                velocity = -gestureRecognizer.velocity(in: containerView).x
            case .trailing:
                velocity = gestureRecognizer.velocity(in: containerView).x
            }
            let shouldDismiss = (abs(percentage) > 0.5 && velocity > 0) || velocity >= 1000
            if shouldDismiss {
                transition?.finish()
            } else {
                if abs(velocity) < 1000 {
                    transition?.completionSpeed = 0.5
                }
                transition?.cancel()
            }
            isPanGestureActive = false
            translationOffset = .zero

        default:
            break
        }
    }

    func isAtTop(scrollView: UIScrollView) -> Bool {
        let frame = scrollView.frame
        let size = scrollView.contentSize
        let canScrollVertically = size.height > frame.size.height
        let canScrollHorizontally = size.width > frame.size.width

        switch edge {
        case .top, .bottom:
            if canScrollHorizontally && !canScrollVertically {
                return false
            }

            let dy = scrollView.contentOffset.y + scrollView.contentInset.top
            if edge == .bottom {
                return dy <= 0
            } else {
                return dy >= size.height - frame.height
            }

        case .leading, .trailing:
            if canScrollVertically && !canScrollHorizontally {
                return false
            }

            let dx = scrollView.contentOffset.x + scrollView.contentInset.left
            if edge == .trailing {
                return dx <= 0
            } else {
                return dx >= size.width - frame.width
            }
        }
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        if let scrollView = otherGestureRecognizer.view as? UIScrollView {
            scrollView.panGestureRecognizer.addTarget(self, action: #selector(onPanGesture(_:)))
            switch edge {
            case .bottom, .trailing:
                translationOffset = CGPoint(
                    x: scrollView.contentOffset.x + scrollView.adjustedContentInset.left,
                    y: scrollView.contentOffset.y + scrollView.adjustedContentInset.top
                )
            case .top, .leading:
                translationOffset = CGPoint(
                    x: scrollView.contentOffset.x + scrollView.adjustedContentInset.left + scrollView.adjustedContentInset.right,
                    y: scrollView.contentOffset.y - scrollView.adjustedContentInset.bottom + scrollView.adjustedContentInset.top
                )
            }
            return false
        }
        return false
    }
}


@available(iOS 14.0, *)
@available(macOS, unavailable)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
final class SlideTransition: UIPercentDrivenInteractiveTransition, UIViewControllerAnimatedTransitioning {

    let isPresenting: Bool
    let options: PresentationLinkTransition.SlideTransitionOptions

    var animator: UIViewPropertyAnimator?

    static let displayCornerRadius: CGFloat = {
        #if targetEnvironment(macCatalyst)
        return 12
        #else
        let key = String("suidaRrenroCyalpsid_".reversed())
        let value = UIScreen.main.value(forKey: key) as? CGFloat ?? 0
        return max(value, 12)
        #endif
    }()

    init(
        isPresenting: Bool,
        options: PresentationLinkTransition.SlideTransitionOptions
    ) {
        self.isPresenting = isPresenting
        self.options = options
        super.init()
    }

    // MARK: - UIViewControllerAnimatedTransitioning

    func transitionDuration(
        using transitionContext: UIViewControllerContextTransitioning?
    ) -> TimeInterval {
        transitionContext?.isAnimated == true ? 0.35 : 0
    }

    func animateTransition(
        using transitionContext: UIViewControllerContextTransitioning
    ) {
        let animator = makeAnimatorIfNeeded(using: transitionContext)
        animator.startAnimation()

        if !transitionContext.isAnimated {
            animator.stopAnimation(false)
            animator.finishAnimation(at: .end)
        }
    }

    func animationEnded(_ transitionCompleted: Bool) {
        wantsInteractiveStart = false
        animator = nil
    }

    func interruptibleAnimator(
        using transitionContext: UIViewControllerContextTransitioning
    ) -> UIViewImplicitlyAnimating {
        let animator = makeAnimatorIfNeeded(using: transitionContext)
        return animator
    }

    func makeAnimatorIfNeeded(
        using transitionContext: UIViewControllerContextTransitioning
    ) -> UIViewPropertyAnimator {
        if let animator = animator {
            return animator
        }

        let isPresenting = isPresenting
        let animator = UIViewPropertyAnimator(
            duration: duration,
            curve: completionCurve
        )

        guard
            let presented = transitionContext.viewController(forKey: isPresenting ? .to : .from),
            let presenting = transitionContext.viewController(forKey: isPresenting ? .from : .to)
        else {
            transitionContext.completeTransition(false)
            return animator
        }

        #if targetEnvironment(macCatalyst)
        let isScaleEnabled = false
        #else
        let isTranslucentBackground = options.options.preferredPresentationBackgroundUIColor.map { color in
            var alpha: CGFloat = 0
            if color.getWhite(nil, alpha: &alpha) {
                return alpha < 1
            }
            return false
        } ?? false
        let isScaleEnabled = options.prefersScaleEffect && !isTranslucentBackground && presenting.view.convert(presenting.view.frame.origin, to: nil).y == 0
        #endif
        let safeAreaInsets = transitionContext.containerView.safeAreaInsets
        let cornerRadius = options.preferredCornerRadius ?? Self.displayCornerRadius

        var dzTransform = CGAffineTransform(scaleX: 0.92, y: 0.92)
        switch options.edge {
        case .top:
            dzTransform = dzTransform.translatedBy(x: 0, y: safeAreaInsets.bottom / 2)
        case .bottom:
            dzTransform = dzTransform.translatedBy(x: 0, y: safeAreaInsets.top / 2)
        case .leading:
            switch presented.traitCollection.layoutDirection {
            case .rightToLeft:
                dzTransform = dzTransform.translatedBy(x: 0, y: safeAreaInsets.left / 2)
            default:
                dzTransform = dzTransform.translatedBy(x: 0, y: safeAreaInsets.right / 2)
            }
        case .trailing:
            switch presented.traitCollection.layoutDirection {
            case .leftToRight:
                dzTransform = dzTransform.translatedBy(x: 0, y: safeAreaInsets.right / 2)
            default:
                dzTransform = dzTransform.translatedBy(x: 0, y: safeAreaInsets.left / 2)
            }
        }

        presented.view.layer.masksToBounds = true
        presented.view.layer.cornerCurve = .continuous

        presenting.view.layer.masksToBounds = true
        presenting.view.layer.cornerCurve = .continuous

        let frame = transitionContext.finalFrame(for: presented)
        if isPresenting {
            transitionContext.containerView.addSubview(presented.view)
            presented.view.frame = frame
            presented.view.transform = presentationTransform(
                presented: presented,
                frame: frame
            )
        } else {
            presented.view.layer.cornerRadius = cornerRadius
            #if !targetEnvironment(macCatalyst)
            if isScaleEnabled {
                presenting.view.transform = dzTransform
                presenting.view.layer.cornerRadius = cornerRadius
            }
            #endif
        }

        presented.additionalSafeAreaInsets.top = -1

        let presentedTransform = isPresenting ? .identity : presentationTransform(
            presented: presented,
            frame: frame
        )
        let presentingTransform = isPresenting && isScaleEnabled ? dzTransform : .identity
        animator.addAnimations {
            presented.view.transform = presentedTransform
            presented.view.layer.cornerRadius = isPresenting ? cornerRadius : 0
            presenting.view.transform = presentingTransform
            if isScaleEnabled {
                presenting.view.layer.cornerRadius = isPresenting ? cornerRadius : 0
            }
        }
        animator.addCompletion { animatingPosition in

            if presented.view.frame.origin.y == 0 {
                presented.view.layer.cornerRadius = 0
            }

            if isScaleEnabled {
                presenting.view.layer.cornerRadius = 0
                presenting.view.transform = .identity
            }

            switch animatingPosition {
            case .end:
                transitionContext.completeTransition(true)
            default:
                transitionContext.completeTransition(false)
            }
        }
        self.animator = animator
        return animator
    }

    private func presentationTransform(
        presented: UIViewController,
        frame: CGRect
    ) -> CGAffineTransform {
        switch options.edge {
        case .top:
            return CGAffineTransform(translationX: 0, y: -frame.maxY)
        case .bottom:
            return CGAffineTransform(translationX: 0, y: frame.maxY)
        case .leading:
            switch presented.traitCollection.layoutDirection {
            case .rightToLeft:
                return CGAffineTransform(translationX: frame.maxX, y: 0)
            default:
                return CGAffineTransform(translationX: -frame.maxX, y: 0)
            }
        case .trailing:
            switch presented.traitCollection.layoutDirection {
            case .leftToRight:
                return CGAffineTransform(translationX: frame.maxX, y: 0)
            default:
                return CGAffineTransform(translationX: -frame.maxX, y: 0)
            }
        }
    }
}

#endif
