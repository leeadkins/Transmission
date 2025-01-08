//
// Copyright (c) Nathan Tannar
//

#if os(iOS)

import SwiftUI
import Engine
import EngineCore
import Turbocharger

/// A modifier that presents a destination view in a new `UIViewController`.
///
/// To present the destination view with an animation, `isPresented` should
/// be updated with a transaction that has an animation. For example:
///
/// ```
/// withAnimation {
///     isPresented = true
/// }
/// ```
///
/// The destination view is presented with the provided `transition`.
/// By default, the ``PresentationLinkTransition/default`` transition is used.
///
/// See Also:
///  - ``PresentationLinkTransition``
///  - ``TransitionReader``
///
/// > Tip: You can implement custom transitions with a `UIPresentationController` and/or
/// `UIViewControllerInteractiveTransitioning` with the ``PresentationLinkTransition/custom(_:)``
///  transition.
///
@available(iOS 14.0, *)
@frozen
public struct PresentationLinkModifier<
    Destination: View
>: ViewModifier {

    var isPresented: Binding<Bool>
    var destination: Destination
    var transition: PresentationLinkTransition

    public init(
        transition: PresentationLinkTransition = .default,
        isPresented: Binding<Bool>,
        destination: Destination
    ) {
        self.isPresented = isPresented
        self.destination = destination
        self.transition = transition
    }

    public func body(content: Content) -> some View {
        content.background(
            PresentationLinkModifierBody(
                transition: transition,
                isPresented: isPresented,
                destination: destination
            )
        )
    }
}

@available(iOS 14.0, *)
extension View {
    /// A modifier that presents a destination view in a new `UIViewController`.
    ///
    /// To present the destination view with an animation, `isPresented` should
    /// be updated with a transaction that has an animation. For example:
    ///
    /// ```
    /// withAnimation {
    ///     isPresented = true
    /// }
    /// ```
    ///
    /// See Also:
    ///  - ``PresentationLinkModifier``
    ///
    public func presentation<Destination: View>(
        transition: PresentationLinkTransition = .default,
        isPresented: Binding<Bool>,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        modifier(
            PresentationLinkModifier(
                transition: transition,
                isPresented: isPresented,
                destination: destination()
            )
        )
    }

    /// A modifier that presents a destination view in a new `UIViewController`.
    ///
    /// To present the destination view with an animation, `isPresented` should
    /// be updated with a transaction that has an animation. For example:
    ///
    /// ```
    /// withAnimation {
    ///     isPresented = true
    /// }
    /// ```
    ///
    /// See Also:
    ///  - ``PresentationLinkModifier``
    ///  
    public func presentation<T, Destination: View>(
        _ value: Binding<T?>,
        transition: PresentationLinkTransition = .default,
        @ViewBuilder destination: (Binding<T>) -> Destination
    ) -> some View {
        presentation(transition: transition, isPresented: value.isNotNil()) {
            OptionalAdapter(value, content: destination)
        }
    }

    /// A modifier that presents a destination `UIViewController`.
    ///
    /// To present the destination view with an animation, `isPresented` should
    /// be updated with a transaction that has an animation. For example:
    ///
    /// ```
    /// withAnimation {
    ///     isPresented = true
    /// }
    /// ```
    /// 
    /// See Also:
    ///  - ``PresentationLinkModifier``
    ///
    @_disfavoredOverload
    public func presentation<ViewController: UIViewController>(
        transition: PresentationLinkTransition = .default,
        isPresented: Binding<Bool>,
        destination: @escaping (ViewControllerRepresentableAdapter<ViewController>.Context) -> ViewController
    ) -> some View {
        presentation(transition: transition, isPresented: isPresented) {
            ViewControllerRepresentableAdapter(destination)
        }
    }
}

@available(iOS 14.0, *)
private struct PresentationLinkModifierBody<
    Destination: View
>: UIViewRepresentable {

    var transition: PresentationLinkTransition
    var isPresented: Binding<Bool>
    var destination: Destination

    @WeakState var presentingViewController: UIViewController?

    typealias DestinationViewController = PresentationHostingController<ModifiedContent<Destination, PresentationBridgeAdapter>>

    func makeUIView(context: Context) -> ViewControllerReader {
        let uiView = ViewControllerReader(
            presentingViewController: $presentingViewController
        )
        return uiView
    }

    func updateUIView(_ uiView: ViewControllerReader, context: Context) {
        if let presentingViewController = presentingViewController, isPresented.wrappedValue {

            context.coordinator.isPresented = isPresented

            let traits = UITraitCollection(traitsFrom: [
                presentingViewController.traitCollection,
                UITraitCollection(userInterfaceStyle: .init(context.environment.colorScheme)),
                UITraitCollection(layoutDirection: .init(context.environment.layoutDirection)),
                UITraitCollection(verticalSizeClass: .init(context.environment.verticalSizeClass)),
                UITraitCollection(horizontalSizeClass: .init(context.environment.horizontalSizeClass)),
                UITraitCollection(accessibilityContrast: .init(context.environment.colorSchemeContrast)),
                UITraitCollection(legibilityWeight: .init(context.environment.legibilityWeight)),
                UITraitCollection(displayScale: context.environment.displayScale),
                UITraitCollection(activeAppearance: .unspecified),
                UITraitCollection(userInterfaceLevel: .elevated)
            ])

            let isAnimated = context.transaction.isAnimated
                || presentingViewController.transitionCoordinator?.isAnimated == true
            let animation = context.transaction.animation
                ?? (isAnimated ? .default : nil)
            context.coordinator.animation = animation
            var isTransitioningPresentationController = false

            if let adapter = context.coordinator.adapter,
                !context.coordinator.isBeingReused
            {
                
                switch (adapter.transition, transition.value) {
                case (.sheet(let oldValue), .sheet(let newValue)):
                    guard #available(iOS 15.0, *), let presentationController = adapter.viewController.presentationController as? SheetPresentationController
                    else {
                        break
                    }
                    PresentationLinkTransition.SheetTransitionOptions.update(
                        presentationController: presentationController,
                        animated: isAnimated,
                        from: oldValue,
                        to: newValue
                    )

                case (.popover(let oldValue), .popover(let newValue)):
                    if let presentationController = adapter.viewController.presentationController as? UIPopoverPresentationController {
                        presentationController.permittedArrowDirections = newValue.permittedArrowDirections(
                            layoutDirection: traits.layoutDirection
                        )
                        if let backgroundColor = newValue.options.preferredPresentationBackgroundUIColor {
                            presentationController.backgroundColor = backgroundColor
                        }
                    } else if #available(iOS 15.0, *) {
                        if let newValue = newValue.adaptiveTransition,
                            let presentationController = adapter.viewController.presentationController as? SheetPresentationController
                        {
                            PresentationLinkTransition.SheetTransitionOptions.update(
                                presentationController: presentationController,
                                animated: isAnimated,
                                from: oldValue.adaptiveTransition ?? .init(),
                                to: newValue
                            )
                        }
                    }

                case (.slide, .slide(let newValue)):
                    if let presentationController = adapter.viewController.presentationController as? SlidePresentationController {
                        presentationController.edge = newValue.edge
                    }

                case (.card, .card(let newValue)):
                    if let presentationController = adapter.viewController.presentationController as? CardPresentationController {
                        presentationController.preferredEdgeInset = newValue.preferredEdgeInset
                        presentationController.preferredCornerRadius = newValue.preferredCornerRadius
                    }

                case (.matchedGeometry, .matchedGeometry(let newValue)):
                    if let presentationController = adapter.viewController.presentationController as? MatchedGeometryPresentationController {
                        presentationController.edges = newValue.edges
                        presentationController.preferredCornerRadius = newValue.preferredCornerRadius
                        presentationController.minimumScaleFactor = newValue.minimumScaleFactor
                    }

                case (.toast, .toast(let newValue)):
                    if let presentationController = adapter.viewController.presentationController as? ToastPresentationController {
                        presentationController.edge = newValue.edge
                    }

                case (.zoom, .zoom):
                    break

                case (.representable, .representable(let options, let transition)):
                    if let presentationController = adapter.viewController.presentationController {
                        func project<T: PresentationLinkTransitionRepresentable>(
                            _ transition: T
                        ) {
                            let context = PresentationLinkTransitionRepresentableContext(
                                sourceView: uiView,
                                options: options,
                                environment: context.environment,
                                transaction: Transaction(animation: animation)
                            )
                            if let presentationController = presentationController as? T.UIPresentationControllerType {
                                transition.updateUIPresentationController(
                                    presentationController: presentationController,
                                    context: context
                                )
                            } else {
                                transition.updateAdaptivePresentationController(
                                    adaptivePresentationController: presentationController,
                                    context: context
                                )
                            }
                        }
                        _openExistential(transition, do: project)
                    }

                case (.default, .default),
                    (.currentContext, .currentContext),
                    (.fullscreen, .fullscreen),
                    (.custom, .custom):
                    break

                default:
                    if context.coordinator.adapter?.transition.options.preferredPresentationBackgroundUIColor != nil {
                        context.coordinator.adapter?.viewController.view.backgroundColor = .systemBackground
                    }
                    context.coordinator.isBeingReused = true
                    isTransitioningPresentationController = true
                }
            }

            if let adapter = context.coordinator.adapter,
                !context.coordinator.isBeingReused
            {
                adapter.transition = transition.value
                adapter.viewController.presentationController?.overrideTraitCollection = traits

                adapter.update(
                    destination: destination,
                    sourceView: uiView,
                    context: context,
                    isPresented: isPresented
                )
            } else {
                let adapter: PresentationLinkDestinationViewControllerAdapter<Destination>
                if let oldValue = context.coordinator.adapter {
                    adapter = oldValue
                    adapter.transition = transition.value
                    adapter.update(
                        destination: destination,
                        sourceView: uiView,
                        context: context,
                        isPresented: isPresented
                    )
                    context.coordinator.isBeingReused = false
                } else {
                    adapter = PresentationLinkDestinationViewControllerAdapter(
                        destination: destination,
                        sourceView: uiView,
                        transition: transition.value,
                        context: context,
                        isPresented: isPresented
                    )
                    context.coordinator.adapter = adapter
                }

                if case .default = adapter.transition { } else {
                    adapter.viewController.transitioningDelegate = context.coordinator
                }

                switch adapter.transition {
                case .`default`:
                    if let presentationController = adapter.viewController.presentationController {
                        presentationController.delegate = context.coordinator
                        presentationController.overrideTraitCollection = traits

                        if #available(iOS 15.0, *),
                           let sheetPresentationController = presentationController as? UISheetPresentationController
                        {
                            sheetPresentationController.delegate = context.coordinator
                            if case .sheet(let options) = adapter.transition,
                                options.prefersSourceViewAlignment
                            {
                                sheetPresentationController.sourceView = uiView
                            }
                        } else if let popoverPresentationController = presentationController as? UIPopoverPresentationController {
                            popoverPresentationController.delegate = context.coordinator
                            popoverPresentationController.sourceView = uiView
                            if case .popover(let options) = adapter.transition {
                                let permittedArrowDirections = options.permittedArrowDirections(
                                    layoutDirection: traits.layoutDirection
                                )
                                popoverPresentationController.permittedArrowDirections = permittedArrowDirections
                                if let backgroundColor = options.options.preferredPresentationBackgroundUIColor {
                                    popoverPresentationController.backgroundColor = backgroundColor
                                }
                            }
                        }
                    }

                case .currentContext:
                    // transitioningDelegate + .custom breaks .overCurrentContext
                    adapter.viewController.modalPresentationStyle = .overCurrentContext
                    adapter.viewController.presentationController?.overrideTraitCollection = traits

                case .fullscreen:
                    adapter.viewController.modalPresentationStyle = .overFullScreen
                    adapter.viewController.presentationController?.overrideTraitCollection = traits

                case .sheet, .popover, .slide, .card, .matchedGeometry, .toast:
                    context.coordinator.sourceView = uiView
                    context.coordinator.overrideTraitCollection = traits
                    adapter.viewController.modalPresentationStyle = .custom

                case .zoom:
                    if #available(iOS 18.0, *) {
                        adapter.viewController.preferredTransition = .zoom { [weak uiView] context in
                            return uiView
                        }
                        adapter.viewController.presentationController?.delegate = context.coordinator
                    } else {
                        context.coordinator.sourceView = uiView
                        context.coordinator.overrideTraitCollection = traits
                        adapter.viewController.modalPresentationStyle = .custom
                    }

                case .representable(_, let transition):
                    assert(!isClassType(transition), "PresentationLinkTransitionRepresentable must be value types (either a struct or an enum); it was a class")
                    context.coordinator.sourceView = uiView
                    context.coordinator.overrideTraitCollection = traits
                    adapter.viewController.modalPresentationStyle = .custom

                case .custom(_, let transition):
                    assert(!isClassType(transition), "PresentationLinkCustomTransition must be value types (either a struct or an enum); it was a class")
                    context.coordinator.sourceView = uiView
                    context.coordinator.overrideTraitCollection = traits
                    adapter.viewController.modalPresentationStyle = .custom
                }

                if isTransitioningPresentationController {
                    adapter.viewController.presentationDelegate = nil
                    adapter.viewController.modalTransitionStyle = .crossDissolve
                } else {
                    // Swizzle to hook up for programatic dismissal
                    adapter.viewController.presentationDelegate = context.coordinator
                }

                var presentingViewController = presentingViewController
                if !transition.value.options.shouldAutomaticallyDismissPresentedView {
                    while let presenting = presentingViewController.presentedViewController {
                        presentingViewController = presenting
                    }
                }
                let present: () -> Void = {
                    guard let viewController = adapter.viewController else { return }
                    presentingViewController.present(
                        viewController,
                        animated: isAnimated
                    ) {
                        if !isPresented.wrappedValue {
                            // Handle `isPresented` changing mid presentation
                            viewController.dismiss(animated: isAnimated)
                        } else {
                            viewController
                                .setNeedsStatusBarAppearanceUpdate(animated: isAnimated)
                            if isTransitioningPresentationController {
                                viewController.presentationDelegate = context.coordinator
                            }
                        }
                    }
                }
                if let presentedViewController = presentingViewController.presentedViewController {
                    let shouldDismiss =
                        isTransitioningPresentationController ||
                        presentedViewController.presentationController.map {
                            $0.delegate?.presentationControllerShouldDismiss?($0) ?? true
                        } ?? true
                    if shouldDismiss {
                        presentedViewController.dismiss(
                            animated: isAnimated && !isTransitioningPresentationController,
                            completion: present
                        )
                    } else {
                        present()
                    }
                } else {
                    present()
                }
            }
        } else if let adapter = context.coordinator.adapter,
            !isPresented.wrappedValue,
            !context.coordinator.isBeingReused
        {
            let isAnimated = context.transaction.isAnimated
            let viewController = adapter.viewController!
            if viewController.presentedViewController != nil {
                (viewController.presentingViewController ?? viewController).dismiss(animated: isAnimated)
            } else if viewController.presentingViewController != nil {
                viewController.dismiss(animated: isAnimated)
            }
            if adapter.transition.options.isDestinationReusable {
                context.coordinator.isBeingReused = true
            } else {
                context.coordinator.adapter = nil
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(isPresented: isPresented)
    }

    final class Coordinator: NSObject,
        UIViewControllerTransitioningDelegate,
        UIAdaptivePresentationControllerDelegate,
        UISheetPresentationControllerDelegate,
        UIPopoverPresentationControllerDelegate,
        UIViewControllerPresentationDelegate
    {
        var isPresented: Binding<Bool>
        var adapter: PresentationLinkDestinationViewControllerAdapter<Destination>?
        var isBeingReused = false
        var animation: Animation?
        unowned var sourceView: UIView!
        var overrideTraitCollection: UITraitCollection?

        init(isPresented: Binding<Bool>) {
            self.isPresented = isPresented
        }

        private func makeContext(
            options: PresentationLinkTransition.Options
        ) -> PresentationLinkTransitionRepresentableContext {
            PresentationLinkTransitionRepresentableContext(
                sourceView: sourceView,
                options: options,
                environment: adapter?.environment ?? .init(),
                transaction: Transaction(animation: animation)
            )
        }

        // MARK: - UIViewControllerPresentationDelegate

        func viewControllerDidDismiss(
            _ presentingViewController: UIViewController?,
            animated: Bool
        ) {
            if isPresented.wrappedValue {
                var transaction = Transaction(animation: animated ? .default : nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    self.isPresented.wrappedValue = false
                }
            }

            // Dismiss already handled by the presentation controller below
            if let presentingViewController {
                presentingViewController.setNeedsStatusBarAppearanceUpdate(animated: animated)
                presentingViewController.fixSwiftUIHitTesting()
            }
        }

        // MARK: - UIAdaptivePresentationControllerDelegate

        func presentationControllerDidDismiss(
            _ presentationController: UIPresentationController
        ) {
            presentationController.presentingViewController.setNeedsStatusBarAppearanceUpdate(animated: true)
            presentationController.presentingViewController.fixSwiftUIHitTesting()
        }

        func presentationControllerShouldDismiss(
            _ presentationController: UIPresentationController
        ) -> Bool {
            guard let transition = adapter?.transition else { return true }
            return transition.options.isInteractive
        }

        func presentationControllerDidAttemptToDismiss(
            _ presentationController: UIPresentationController
        ) {
            presentationController.presentedViewController.fixSwiftUIHitTesting()
        }

        func adaptivePresentationStyle(
            for controller: UIPresentationController
        ) -> UIModalPresentationStyle {
            adaptivePresentationStyle(
                for: controller,
                traitCollection: controller.traitCollection
            )
        }

        func adaptivePresentationStyle(
            for controller: UIPresentationController,
            traitCollection: UITraitCollection
        ) -> UIModalPresentationStyle {
            switch adapter?.transition {
            case .popover(let options):
                return options.adaptiveTransition != nil && traitCollection.horizontalSizeClass == .compact ? .pageSheet : .none

            case .representable(_, let transition):
                return transition.adaptivePresentationStyle(
                    for: controller,
                    traitCollection: traitCollection
                )

            case .custom(_, let transition):
                return transition.adaptivePresentationStyle(
                    for: controller,
                    traitCollection: traitCollection
                )

            default:
                return .none
            }
        }

        func presentationController(
            _ presentationController: UIPresentationController,
            prepare adaptivePresentationController: UIPresentationController
        ) {
            guard let adapter else { return }
            switch adapter.transition {
            case .popover(let options):
                if #available(iOS 15.0, *) {
                    if let options = options.adaptiveTransition,
                        let presentationController = adaptivePresentationController as? SheetPresentationController
                    {
                        PresentationLinkTransition.SheetTransitionOptions.update(
                            presentationController: presentationController,
                            animated: false,
                            from: .init(),
                            to: options
                        )
                    }
                }

            case .representable(let options, let transition):
                let context = PresentationLinkTransitionRepresentableContext(
                    sourceView: sourceView,
                    options: options,
                    environment: adapter.environment,
                    transaction: Transaction(animation: animation)
                )
                transition.updateAdaptivePresentationController(
                    adaptivePresentationController: adaptivePresentationController,
                    context: context
                )

            case .custom(_, let transition):
                transition.presentationController(presentationController, prepare: adaptivePresentationController)

            default:
                break
            }
        }

        // MARK: - UIViewControllerTransitioningDelegate

        func animationController(
            forPresented presented: UIViewController,
            presenting: UIViewController,
            source: UIViewController
        ) -> UIViewControllerAnimatedTransitioning? {
            guard adapter?.viewController.presentationDelegate == self else { return nil }
            switch adapter?.transition {
            case .sheet(let options):
                #if targetEnvironment(macCatalyst)
                if #available(iOS 15.0, *) {
                    let transition = SlideTransition(
                        isPresenting: true,
                        options: .init(
                            edge: .bottom,
                            prefersScaleEffect: false,
                            preferredCornerRadius: options.preferredCornerRadius,
                            isInteractive: options.isInteractive,
                            options: options.options
                        )
                    )
                    transition.wantsInteractiveStart = false
                    return transition
                }
                #endif
                return nil

            case .slide(let options):
                let transition = SlideTransition(
                    isPresenting: true,
                    options: options,
                    animation: animation
                )
                transition.wantsInteractiveStart = false
                return transition

            case .card:
                let transition = PresentationControllerTransition(
                    isPresenting: true,
                    animation: animation
                )
                transition.wantsInteractiveStart = false
                return transition

            case .matchedGeometry:
                let transition = MatchedGeometryTransition(
                    sourceView: sourceView,
                    isPresenting: true,
                    animation: animation
                )
                transition.wantsInteractiveStart = false
                return transition

            case .toast(let options):
                let transition = ToastTransition(
                    isPresenting: true,
                    animation: animation,
                    edge: options.edge
                )
                transition.wantsInteractiveStart = false
                return transition

            case .representable(let options, let transition):
                return transition.animationController(
                    forPresented: presented,
                    presenting: presenting,
                    context: makeContext(options: options)
                )

            case .custom(_, let transition):
                return transition.animationController(
                    forPresented: presented,
                    presenting: presenting
                )

            default:
                return nil
            }
        }

        func animationController(
            forDismissed dismissed: UIViewController
        ) -> UIViewControllerAnimatedTransitioning? {
            guard adapter?.viewController.presentationDelegate == self else { return nil }
            switch adapter?.transition {
            case .sheet(let options):
                #if targetEnvironment(macCatalyst)
                if #available(iOS 15.0, *),
                    let presentationController = dismissed.presentationController as? MacSheetPresentationController
                {
                    let transition = MacSheetTransition(
                        isPresenting: false,
                        options: .init(
                            edge: .bottom,
                            prefersScaleEffect: false,
                            preferredCornerRadius: options.preferredCornerRadius,
                            isInteractive: options.isInteractive,
                            options: options.options
                        )
                    )
                    transition.wantsInteractiveStart = options.isInteractive && presentationController.wantsInteractiveTransition
                    presentationController.transition(with: transition)
                    return transition
                }
                #endif
                return nil

            case .slide(let options):
                guard let presentationController = dismissed.presentationController as? SlidePresentationController else {
                    return nil
                }
                let transition = SlideTransition(
                    isPresenting: false,
                    options: options,
                    animation: animation
                )
                transition.wantsInteractiveStart = options.options.isInteractive && presentationController.wantsInteractiveTransition
                presentationController.transition(with: transition)
                return transition

            case .card(let options):
                guard let presentationController = dismissed.presentationController as? CardPresentationController else {
                    return nil
                }
                let transition = PresentationControllerTransition(
                    isPresenting: false,
                    animation: animation
                )
                transition.wantsInteractiveStart = options.options.isInteractive && presentationController.wantsInteractiveTransition
                presentationController.transition(with: transition)
                return transition

            case .matchedGeometry(let options):
                guard let presentationController = dismissed.presentationController as? MatchedGeometryPresentationController else {
                    return nil
                }
                let transition = MatchedGeometryTransition(
                    sourceView: sourceView,
                    isPresenting: false,
                    animation: animation
                )
                transition.wantsInteractiveStart = options.options.isInteractive && presentationController.wantsInteractiveTransition
                presentationController.transition(with: transition)
                return transition

            case .toast(let options):
                guard let presentationController = dismissed.presentationController as? ToastPresentationController else {
                    return nil
                }
                let transition = ToastTransition(
                    isPresenting: false,
                    animation: animation,
                    edge: options.edge
                )
                transition.wantsInteractiveStart = options.options.isInteractive && presentationController.wantsInteractiveTransition
                presentationController.transition(with: transition)
                return transition

            case .representable(let options, let transition):
                return transition.animationController(
                    forDismissed: dismissed,
                    context: makeContext(options: options)
                )

            case .custom(_, let transition):
                return transition.animationController(forDismissed: dismissed)

            default:
                return nil
            }
        }

        func interactionControllerForPresentation(
            using animator: UIViewControllerAnimatedTransitioning
        ) -> UIViewControllerInteractiveTransitioning? {
            guard adapter?.viewController.presentationDelegate == self else { return nil }
            switch adapter?.transition {
            case .representable(let options, let transition):
                return transition.interactionControllerForPresentation(
                    using: animator,
                    context: makeContext(options: options)
                )

            case .custom(_, let transition):
                return transition.interactionControllerForPresentation(using: animator)

            default:
                return nil
            }
        }

        func interactionControllerForDismissal(
            using animator: UIViewControllerAnimatedTransitioning
        ) -> UIViewControllerInteractiveTransitioning? {
            guard adapter?.viewController.presentationDelegate == self else { return nil }
            switch adapter?.transition {
            case .sheet:
                #if targetEnvironment(macCatalyst)
                if #available(iOS 15.0, *) {
                    return animator as? MacSheetTransition
                }
                #endif
                return nil

            case .slide:
                return animator as? SlideTransition

            case .card:
                return animator as? PresentationControllerTransition

            case .matchedGeometry:
                return animator as? MatchedGeometryTransition

            case .toast:
                return animator as? ToastTransition

            case .representable(let options, let transition):
                return transition.interactionControllerForDismissal(
                    using: animator,
                    context: makeContext(options: options)
                )

            case .custom(_, let transition):
                return transition.interactionControllerForDismissal(using: animator)

            default:
                return nil
            }
        }

        func presentationController(
            forPresented presented: UIViewController,
            presenting: UIViewController?,
            source: UIViewController
        ) -> UIPresentationController? {
            guard let adapter else { return nil }
            switch adapter.transition {
            case .sheet(let configuration):
                if #available(iOS 15.0, *) {
                    #if targetEnvironment(macCatalyst)
                    let presentationController = MacSheetPresentationController(
                        presentedViewController: presented,
                        presenting: presenting
                    )
                    presentationController.preferredCornerRadius = configuration.preferredCornerRadius
                    let selected = configuration.selected?.wrappedValue
                    presentationController.detent = configuration.detents.first(where: { $0.identifier == selected }) ?? configuration.detents.first ?? .large
                    presentationController.selected = configuration.selected
                    presentationController.largestUndimmedDetentIdentifier = configuration.largestUndimmedDetentIdentifier
                    return presentationController
                    #else
                    
                    var presentationController: UISheetPresentationController
                    
                    if let sheetType = configuration.sheetPresentationType,
                       let sheetClass = sheetType as? UISheetPresentationController.Type {
                        presentationController = sheetClass.init(
                            presentedViewController: presented,
                            presenting: presenting
                        )
                    } else {
                        presentationController = SheetPresentationController(
                            presentedViewController: presented,
                            presenting: presenting
                        )
                    }
                    
                    
                    presentationController.detents = configuration.detents.map {
                        $0.toUIKit(in: presentationController)
                    }
                    presentationController.selectedDetentIdentifier = (configuration.selected?.wrappedValue ?? configuration.detents.first?.identifier)?.toUIKit()
                    presentationController.largestUndimmedDetentIdentifier = configuration.largestUndimmedDetentIdentifier?.toUIKit()
                    presentationController.prefersGrabberVisible = configuration.prefersGrabberVisible
                    presentationController.preferredCornerRadius = configuration.preferredCornerRadius
                    presentationController.prefersScrollingExpandsWhenScrolledToEdge = configuration.prefersScrollingExpandsWhenScrolledToEdge
                    presentationController.prefersEdgeAttachedInCompactHeight = configuration.prefersEdgeAttachedInCompactHeight
                    presentationController.widthFollowsPreferredContentSizeWhenEdgeAttached = configuration.widthFollowsPreferredContentSizeWhenEdgeAttached
                    if configuration.prefersSourceViewAlignment {
                        presentationController.sourceView = sourceView
                    }
//                    presentationController.preferredBackgroundColor = configuration.options.preferredPresentationBackgroundUIColor
                    presentationController.overrideTraitCollection = overrideTraitCollection
                    presentationController.delegate = self
                    return presentationController
                    #endif
                } else {
                    // Fallback on earlier versions
                    let presentationController = PresentationController(
                        presentedViewController: presented,
                        presenting: presenting
                    )
                    presentationController.overrideTraitCollection = overrideTraitCollection
                    presentationController.delegate = self
                    return presentationController
                }

            case .popover(let options):
                let presentationController = UIPopoverPresentationController(
                    presentedViewController: presented,
                    presenting: presenting
                )
                presentationController.canOverlapSourceViewRect = options.canOverlapSourceViewRect
                presentationController.permittedArrowDirections = options.permittedArrowDirections(
                    layoutDirection: presentationController.traitCollection.layoutDirection
                )
                presentationController.sourceView = sourceView
                presentationController.overrideTraitCollection = overrideTraitCollection
                presentationController.delegate = self
                return presentationController

            case .slide(let options):
                let presentationController = SlidePresentationController(
                    edge: options.edge,
                    presentedViewController: presented,
                    presenting: presenting
                )
                presentationController.overrideTraitCollection = overrideTraitCollection
                presentationController.delegate = self
                return presentationController

            case .card(let options):
                let presentationController = CardPresentationController(
                    preferredEdgeInset: options.preferredEdgeInset,
                    preferredCornerRadius: options.preferredCornerRadius,
                    presentedViewController: presented,
                    presenting: presenting
                )
                presentationController.overrideTraitCollection = overrideTraitCollection
                presentationController.delegate = self
                return presentationController

            case .matchedGeometry(let options):
                let presentationController = MatchedGeometryPresentationController(
                    edges: options.edges,
                    preferredCornerRadius: options.preferredCornerRadius,
                    minimumScaleFactor: options.minimumScaleFactor,
                    presentedViewController: presented,
                    presenting: presenting
                )
                presentationController.overrideTraitCollection = overrideTraitCollection
                presentationController.delegate = self
                return presentationController

            case .toast(let options):
                let presentationController = ToastPresentationController(
                    edge: options.edge,
                    presentedViewController: presented,
                    presenting: presenting
                )
                presentationController.overrideTraitCollection = overrideTraitCollection
                presentationController.delegate = self
                return presentationController

            case .representable(let options, let transition):
                let presentationController = transition.makeUIPresentationController(
                    presented: presented,
                    presenting: presenting,
                    context: makeContext(options: options)
                )
                presentationController.overrideTraitCollection = overrideTraitCollection
                presentationController.delegate = self
                return presentationController

            case .custom(_, let transition):
                let presentationController = transition.presentationController(
                    sourceView: sourceView,
                    presented: presented,
                    presenting: presenting
                )
                presentationController.overrideTraitCollection = overrideTraitCollection
                presentationController.delegate = self
                return presentationController

            default:
                return nil
            }
        }

        func presentationController(
            _ presentationController: UIPresentationController,
            willPresentWithAdaptiveStyle style: UIModalPresentationStyle,
            transitionCoordinator: UIViewControllerTransitionCoordinator?
        ) {
            #if !targetEnvironment(macCatalyst)
            if #available(iOS 15.0, *) {
                if let sheetPresentationController = presentationController as? SheetPresentationController {
                    transitionCoordinator?.animate(alongsideTransition: { _ in
                        self.sheetPresentationControllerDidChangeSelectedDetentIdentifier(sheetPresentationController)
                    })
                }
            }
            #endif
        }

        // MARK: - UISheetPresentationControllerDelegate

        @available(iOS 15.0, *)
        @available(macOS, unavailable)
        @available(tvOS, unavailable)
        @available(watchOS, unavailable)
        func sheetPresentationControllerDidChangeSelectedDetentIdentifier(
            _ sheetPresentationController: UISheetPresentationController
        ) {
            if case .sheet(let configuration) = adapter?.transition {
                func applySelection() {
                    configuration.selected?.wrappedValue = sheetPresentationController.selectedDetentIdentifier.map {
                        .init($0.rawValue)
                    }
                }

                if sheetPresentationController.selectedDetentIdentifier?.rawValue == PresentationLinkTransition.SheetTransitionOptions.Detent.ideal.identifier.rawValue {
                    if #available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *) {
                        sheetPresentationController.invalidateDetents()
                        applySelection()
                    } else {
                        sheetPresentationController.detents = configuration.detents.map {
                            $0.toUIKit(in: sheetPresentationController)
                        }
                        withCATransaction {
                            applySelection()
                        }
                    }
                } else {
                    applySelection()
                }
            }
        }

        // MARK: - UIPopoverPresentationControllerDelegate

        func prepareForPopoverPresentation(
            _ popoverPresentationController: UIPopoverPresentationController
        ) {
            popoverPresentationController.presentedViewController.view.layoutIfNeeded()
        }
    }

    static func dismantleUIView(_ uiView: UIViewType, coordinator: Coordinator) {
        if let adapter = coordinator.adapter {
            if adapter.transition.options.shouldAutomaticallyDismissDestination {
                let isAnimated = coordinator.animation != nil
                withCATransaction {
                    adapter.viewController.dismiss(animated: isAnimated)
                }
            }
            coordinator.adapter = nil
        }
    }
}

@available(iOS 14.0, *)
private class PresentationLinkDestinationViewControllerAdapter<
    Destination: View
> {

    typealias DestinationController = PresentationHostingController<ModifiedContent<Destination, PresentationBridgeAdapter>>

    var viewController: UIViewController!
    var context: Any!

    var transition: PresentationLinkTransition.Value
    var environment: EnvironmentValues
    var isPresented: Binding<Bool>
    var conformance: ProtocolConformance<UIViewControllerRepresentableProtocolDescriptor>? = nil

    init(
        destination: Destination,
        sourceView: UIView,
        transition: PresentationLinkTransition.Value,
        context: PresentationLinkModifierBody<Destination>.Context,
        isPresented: Binding<Bool>
    ) {
        self.transition = transition
        self.environment = context.environment
        self.isPresented = isPresented
        if let conformance = UIViewControllerRepresentableProtocolDescriptor.conformance(of: Destination.self) {
            self.conformance = conformance
            update(
                destination: destination,
                sourceView: sourceView,
                context: context,
                isPresented: isPresented
            )
        } else {
            let viewController = DestinationController(
                content: destination.modifier(
                    PresentationBridgeAdapter(
                        presentationCoordinator: PresentationCoordinator(
                            isPresented: isPresented.wrappedValue,
                            dismissBlock: { [weak self] in
                                self?.dismiss($0, $1)
                            }
                        )
                    )
                )
            )
            transition.update(viewController)
            self.viewController = viewController
        }
    }

    deinit {
        switch transition {
        case .sheet(let configuration):
            withCATransaction {
                configuration.selected?.wrappedValue = nil
            }
        default:
            break
        }
        if let conformance = conformance {
            var visitor = Visitor(
                destination: nil,
                isPresented: .constant(false),
                sourceView: nil,
                context: nil,
                adapter: self
            )
            conformance.visit(visitor: &visitor)
        }
    }

    func update(
        destination: Destination,
        sourceView: UIView,
        context: PresentationLinkModifierBody<Destination>.Context,
        isPresented: Binding<Bool>
    ) {
        environment = context.environment
        self.isPresented = isPresented
        if let conformance = conformance {
            var visitor = Visitor(
                destination: destination,
                isPresented: isPresented,
                sourceView: sourceView,
                context: context,
                adapter: self
            )
            conformance.visit(visitor: &visitor)
            switch transition {
            case .representable(let options, _), .custom(let options, _):
                viewController.modalPresentationCapturesStatusBarAppearance = options.modalPresentationCapturesStatusBarAppearance
            default:
                break
            }
        } else {
            let viewController = viewController as! DestinationController
            viewController.content = destination.modifier(
                PresentationBridgeAdapter(
                    presentationCoordinator: PresentationCoordinator(
                        isPresented: isPresented.wrappedValue,
                        dismissBlock: { [weak self] in self?.dismiss($0, $1) }
                    )
                )
            )
            transition.update(viewController)
        }
    }

    func dismiss(_ count: Int, _ transaction: Transaction) {
        guard let viewController, count > 0 else { return }
        let presentingViewController = {
            var remaining = count
            var presentingViewController = viewController
            while remaining > 0, let next = presentingViewController.presentingViewController {
                presentingViewController = next
                remaining -= 1
            }
            return presentingViewController
        }()
        let isAnimated = transaction.isAnimated
            || viewController.transitionCoordinator?.isAnimated == true
        presentingViewController.dismiss(animated: isAnimated) {
            withTransaction(transaction) {
                self.isPresented.wrappedValue = false
            }
        }
    }

    private struct Context<Coordinator> {
        // Only `UIViewRepresentable` uses V4
        struct V4 {
            struct RepresentableContextValues {
                enum EnvironmentStorage {
                    case eager(EnvironmentValues)
                    case lazy(() -> EnvironmentValues)
                }
                var preferenceBridge: AnyObject?
                var transaction: Transaction
                var environmentStorage: EnvironmentStorage
            }

            var values: RepresentableContextValues
            var coordinator: Coordinator

            var environment: EnvironmentValues {
                get {
                    switch values.environmentStorage {
                    case .eager(let environment):
                        return environment
                    case .lazy(let block):
                        return block()
                    }
                }
                set {
                    values.environmentStorage = .eager(newValue)
                }
            }
        }

        struct V1 {
            var coordinator: Coordinator
            var transaction: Transaction
            var environment: EnvironmentValues
            var preferenceBridge: AnyObject?
        }
    }

    private struct Visitor: ViewVisitor {
        var destination: Destination?
        var isPresented: Binding<Bool>
        var sourceView: UIView?
        var context: PresentationLinkModifierBody<Destination>.Context?
        var adapter: PresentationLinkDestinationViewControllerAdapter<Destination>

        mutating func visit<Content>(type: Content.Type) where Content: UIViewControllerRepresentable {
            guard
                let destination = destination.map({ unsafeBitCast($0, to: Content.self) }),
                let context = context
            else {
                if let context = adapter.context, let viewController = adapter.viewController as? Content.UIViewControllerType {
                    func project<T>(_ value: T) {
                        let coordinator = unsafeBitCast(value, to: Content.Context.self).coordinator
                        Content.dismantleUIViewController(viewController, coordinator: coordinator)
                    }
                    _openExistential(context, do: project)
                }
                return
            }
            if adapter.context == nil {
                let coordinator = destination.makeCoordinator()
                let preferenceBridge: AnyObject?
                if #available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, visionOS 1.0, *) {
                    preferenceBridge = unsafeBitCast(
                        context,
                        to: Context<PresentationLinkModifierBody<Destination>.Coordinator>.V4.self
                    ).values.preferenceBridge
                } else {
                    preferenceBridge = unsafeBitCast(
                        context,
                        to: Context<PresentationLinkModifierBody<Destination>.Coordinator>.V1.self
                    ).preferenceBridge
                }
                let context = Context<Content.Coordinator>.V1(
                    coordinator: coordinator,
                    transaction: context.transaction,
                    environment: context.environment,
                    preferenceBridge: preferenceBridge
                )
                adapter.context = unsafeBitCast(context, to: Content.Context.self)
            }
            func project<T>(_ value: T) -> Content.Context {
                let presentationCoordinator = PresentationCoordinator(
                    isPresented: isPresented.wrappedValue,
                    sourceView: sourceView,
                    dismissBlock: { [weak adapter] in
                        adapter?.dismiss($0, $1)
                    }
                )
                var ctx = unsafeBitCast(value, to: Context<Content.Coordinator>.V1.self)
                ctx.environment.presentationCoordinator = presentationCoordinator
                return unsafeBitCast(ctx, to: Content.Context.self)
            }
            let ctx = _openExistential(adapter.context!, do: project)
            if adapter.viewController == nil {
                adapter.viewController = destination.makeUIViewController(context: ctx)
            }
            let viewController = adapter.viewController as! Content.UIViewControllerType
            destination.updateUIViewController(viewController, context: ctx)
        }
    }
}

@available(iOS 14.0, *)
extension PresentationLinkTransition.Value {

    func update<Content: View>(_ viewController: PresentationHostingController<Content>) {

        viewController.modalPresentationCapturesStatusBarAppearance = options.modalPresentationCapturesStatusBarAppearance
        if let backgroundColor = options.preferredPresentationBackgroundUIColor {
            viewController.view.backgroundColor = backgroundColor
        }

        switch self {
        case .sheet(let options):
            if #available(iOS 15.0, *) {
                viewController.tracksContentSize = options.widthFollowsPreferredContentSizeWhenEdgeAttached || options.detents.contains(where: { $0.identifier == .ideal || $0.resolution != nil })
            } else {
                viewController.tracksContentSize = options.widthFollowsPreferredContentSizeWhenEdgeAttached
            }

        case .popover:
            viewController.tracksContentSize = true

        default:
            viewController.tracksContentSize = options.tracksContentSize
        }
    }
}

#endif
