// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import UIKit
import Common

final class LocationView: UIView, LocationTextFieldDelegate, ThemeApplicable, AccessibilityActionsSource {
    // MARK: - Properties
    private enum UX {
        static let horizontalSpace: CGFloat = 8
        static let gradientViewWidth: CGFloat = 40
        static let iconContainerCornerRadius: CGFloat = 8
        static let lockIconImageViewSize = CGSize(width: 40, height: 24)
    }

    private var urlAbsolutePath: String?
    private var searchTerm: String?
    private var notifyTextChanged: (() -> Void)?
    private var onTapLockIcon: ((UIButton) -> Void)?
    private var onLongPress: (() -> Void)?
    private weak var delegate: LocationViewDelegate?
    private var isUnifiedSearchEnabled = false

    private var isEditing = false
    private var isURLTextFieldEmpty: Bool {
        urlTextField.text?.isEmpty == true
    }

    private var doesURLTextFieldExceedViewWidth: Bool {
        guard let text = urlTextField.text, let font = urlTextField.font else {
            return false
        }
        let locationViewWidth = frame.width - (UX.horizontalSpace * 2)
        let fontAttributes = [NSAttributedString.Key.font: font]
        let urlTextFieldWidth = text.size(withAttributes: fontAttributes).width
        return urlTextFieldWidth >= locationViewWidth
    }

    private var dotWidth: CGFloat {
        guard let font = urlTextField.font else { return 0 }
        let fontAttributes = [NSAttributedString.Key.font: font]
        let width = "...".size(withAttributes: fontAttributes).width
        return CGFloat(width)
    }

    private lazy var urlTextFieldColor: UIColor = .black
    private lazy var urlTextFieldSubdomainColor: UIColor = .clear
    private lazy var gradientLayer = CAGradientLayer()
    private lazy var gradientView: UIView = .build()

    private var clearButtonWidthConstraint: NSLayoutConstraint?
    private var urlTextFieldLeadingConstraint: NSLayoutConstraint?
    private var iconContainerStackViewLeadingConstraint: NSLayoutConstraint?
    private var lockIconWidthAnchor: NSLayoutConstraint?

    // MARK: - Search Engine / Lock Image
    private lazy var iconContainerStackView: UIStackView = .build { view in
        view.axis = .horizontal
        view.alignment = .center
        view.distribution = .fill
    }
    private lazy var iconContainerBackgroundView: UIView = .build { view in
        view.layer.cornerRadius = UX.iconContainerCornerRadius
    }
    private lazy var searchEngineContentView: SearchEngineView = .build()
    private lazy var lockIconButton: UIButton = .build { button in
        button.contentMode = .scaleAspectFit
        button.addTarget(self, action: #selector(self.didTapLockIcon), for: .touchUpInside)
    }

    // MARK: - URL Text Field
    private lazy var urlTextField: LocationTextField = .build { [self] urlTextField in
        urlTextField.backgroundColor = .clear
        urlTextField.font = FXFontStyles.Regular.body.scaledFont()
        urlTextField.adjustsFontForContentSizeCategory = true
        urlTextField.autocompleteDelegate = self
        urlTextField.accessibilityActionsSource = self
    }

    // MARK: - Init
    override init(frame: CGRect) {
        super.init(frame: .zero)
        setupLayout()
        setupGradientLayer()
        addLongPressGestureRecognizer()

        urlTextField.addTarget(self, action: #selector(LocationView.textDidChange), for: .editingChanged)
        notifyTextChanged = { [self] in
            guard urlTextField.isEditing else { return }

            urlAbsolutePath = urlTextField.text?.lowercased()
            delegate?.locationViewDidEnterText(urlAbsolutePath ?? "")
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func becomeFirstResponder() -> Bool {
        super.becomeFirstResponder()
        return urlTextField.becomeFirstResponder()
    }

    override func resignFirstResponder() -> Bool {
        super.resignFirstResponder()
        return urlTextField.resignFirstResponder()
    }

    func configure(_ state: LocationViewState, delegate: LocationViewDelegate, isUnifiedSearchEnabled: Bool) {
        searchEngineContentView.configure(state, delegate: delegate, isUnifiedSearchEnabled: isUnifiedSearchEnabled)
        configureLockIconButton(state)
        configureURLTextField(state)
        configureA11y(state)
        formatAndTruncateURLTextField()
        updateIconContainer()
        self.delegate = delegate
        self.isUnifiedSearchEnabled = isUnifiedSearchEnabled
        searchTerm = state.searchTerm
        onLongPress = state.onLongPress
    }

    func setAutocompleteSuggestion(_ suggestion: String?) {
        urlTextField.setAutocompleteSuggestion(suggestion)
    }

    // MARK: - Layout
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        DispatchQueue.main.async { [self] in
            formatAndTruncateURLTextField()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateGradient()
        updateURLTextFieldLeadingConstraintBasedOnState()
    }

    private func setupLayout() {
        if isUnifiedSearchEnabled {
            // TODO FXIOS-10193 Update search engine icon for Unified Search
        }

        addSubviews(urlTextField, iconContainerStackView, gradientView)
        iconContainerStackView.addSubview(iconContainerBackgroundView)
        iconContainerStackView.addArrangedSubview(searchEngineContentView)

        urlTextFieldLeadingConstraint = urlTextField.leadingAnchor.constraint(
            equalTo: iconContainerStackView.trailingAnchor)
        urlTextFieldLeadingConstraint?.isActive = true

        iconContainerStackViewLeadingConstraint = iconContainerStackView.leadingAnchor.constraint(equalTo: leadingAnchor)
        iconContainerStackViewLeadingConstraint?.isActive = true

        NSLayoutConstraint.activate([
            gradientView.topAnchor.constraint(equalTo: urlTextField.topAnchor),
            gradientView.bottomAnchor.constraint(equalTo: urlTextField.bottomAnchor),
            gradientView.leadingAnchor.constraint(equalTo: iconContainerStackView.trailingAnchor),
            gradientView.widthAnchor.constraint(equalToConstant: UX.gradientViewWidth),

            urlTextField.topAnchor.constraint(equalTo: topAnchor),
            urlTextField.bottomAnchor.constraint(equalTo: bottomAnchor),
            urlTextField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -UX.horizontalSpace),

            iconContainerBackgroundView.topAnchor.constraint(equalTo: urlTextField.topAnchor),
            iconContainerBackgroundView.bottomAnchor.constraint(equalTo: urlTextField.bottomAnchor),
            iconContainerBackgroundView.leadingAnchor.constraint(lessThanOrEqualTo: urlTextField.leadingAnchor),
            iconContainerBackgroundView.trailingAnchor.constraint(equalTo: iconContainerStackView.trailingAnchor),

            lockIconButton.heightAnchor.constraint(equalToConstant: UX.lockIconImageViewSize.height),
            lockIconButton.widthAnchor.constraint(equalToConstant: UX.lockIconImageViewSize.width),

            iconContainerStackView.topAnchor.constraint(equalTo: topAnchor),
            iconContainerStackView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func setupGradientLayer() {
        gradientLayer.locations = [0, 1]
        gradientLayer.startPoint = CGPoint(x: 0.0, y: 0.5)
        gradientLayer.endPoint = CGPoint(x: 1.0, y: 0.5)
        gradientView.layer.addSublayer(gradientLayer)
    }

    private func updateGradient() {
        let showGradientForLongURL = doesURLTextFieldExceedViewWidth && !isEditing
        gradientView.isHidden = !showGradientForLongURL
        gradientLayer.frame = gradientView.bounds
    }

    private func updateURLTextFieldLeadingConstraintBasedOnState() {
        let shouldAdjustForOverflow = doesURLTextFieldExceedViewWidth && !isEditing
        let shouldAdjustForNonEmpty = !isURLTextFieldEmpty && !isEditing

        // hide the leading "..." by moving them behind the lock icon
        if shouldAdjustForOverflow {
            updateURLTextFieldLeadingConstraint(constant: -dotWidth)
        } else if shouldAdjustForNonEmpty {
            updateURLTextFieldLeadingConstraint()
        } else {
            updateURLTextFieldLeadingConstraint(constant: UX.horizontalSpace)
        }
    }

    private func updateURLTextFieldLeadingConstraint(constant: CGFloat = 0) {
        urlTextFieldLeadingConstraint?.constant = constant
    }

    private func removeContainerIcons() {
        iconContainerStackView.removeAllArrangedViews()
    }

    private func updateIconContainer() {
        guard !isEditing else {
            updateUIForSearchEngineDisplay()
            return
        }

        if isURLTextFieldEmpty {
            updateUIForSearchEngineDisplay()
        } else {
            updateUIForLockIconDisplay()
        }
    }

    private func updateUIForSearchEngineDisplay() {
        removeContainerIcons()
        iconContainerStackView.addArrangedSubview(searchEngineContentView)
        updateURLTextFieldLeadingConstraint(constant: UX.horizontalSpace)
        iconContainerStackViewLeadingConstraint?.constant = UX.horizontalSpace
        updateGradient()
    }

    private func updateUIForLockIconDisplay() {
        guard !isEditing else { return }
        removeContainerIcons()
        iconContainerStackView.addArrangedSubview(lockIconButton)
        updateURLTextFieldLeadingConstraint()
        iconContainerStackViewLeadingConstraint?.constant = 0
        updateGradient()
    }

    private func updateWidthForLockIcon(_ width: CGFloat) {
        lockIconWidthAnchor?.isActive = false
        lockIconWidthAnchor = lockIconButton.widthAnchor.constraint(equalToConstant: width)
        lockIconWidthAnchor?.isActive = true
    }

    // MARK: - `urlTextField` Configuration
    private func configureURLTextField(_ state: LocationViewState) {
        isEditing = state.isEditing
        if state.isEditing {
            urlTextField.text = (state.searchTerm != nil) ? state.searchTerm : state.url?.absoluteString
        } else {
            urlTextField.text = state.url?.absoluteString
        }

        urlTextField.placeholder = state.urlTextFieldPlaceholder
        urlAbsolutePath = state.url?.absoluteString

        let shouldShowKeyboard = state.isEditing && !state.isScrollingDuringEdit
        _ = shouldShowKeyboard ? becomeFirstResponder() : resignFirstResponder()

        // Start overlay mode & select text when in edit mode with a search term
        if shouldShowKeyboard == true && state.shouldSelectSearchTerm == true {
            urlTextField.selectAll(nil)
        }
    }

    private func formatAndTruncateURLTextField() {
        guard !isEditing else { return }

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byTruncatingHead

        let urlString = urlAbsolutePath ?? ""
        let (subdomain, normalizedHost) = URL.getSubdomainAndHost(from: urlString)

        let attributedString = NSMutableAttributedString(
            string: normalizedHost,
            attributes: [.foregroundColor: urlTextFieldColor])

        if let subdomain {
            let range = NSRange(location: 0, length: subdomain.count)
            attributedString.addAttribute(.foregroundColor, value: urlTextFieldSubdomainColor, range: range)
        }
        attributedString.addAttribute(
            .paragraphStyle,
            value: paragraphStyle,
            range: NSRange(
                location: 0,
                length: attributedString.length
            )
        )
        urlTextField.attributedText = attributedString
    }

    // MARK: - `lockIconButton` Configuration
    private func configureLockIconButton(_ state: LocationViewState) {
        guard let lockIconImageName = state.lockIconImageName else {
            updateWidthForLockIcon(0)
            return
        }
        updateWidthForLockIcon(UX.lockIconImageViewSize.width)

        let lockImage = UIImage(named: lockIconImageName)?.withRenderingMode(.alwaysTemplate)
        lockIconButton.setImage(lockImage, for: .normal)
        onTapLockIcon = state.onTapLockIcon
    }

    // MARK: - Gesture Recognizers
    private func addLongPressGestureRecognizer() {
        let longPressRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(LocationView.handleLongPress))
        urlTextField.addGestureRecognizer(longPressRecognizer)
    }

    // MARK: - Selectors
    @objc
    func textDidChange(_ textField: UITextField) {
        notifyTextChanged?()
    }

    @objc
    private func didTapLockIcon() {
        onTapLockIcon?(lockIconButton)
    }

    @objc
    private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
        if recognizer.state == .began {
            onLongPress?()
        }
    }

    // MARK: - LocationTextFieldDelegate
    func locationTextField(_ textField: LocationTextField, didEnterText text: String) {
        delegate?.locationViewDidEnterText(text)
    }

    func locationTextFieldShouldReturn(_ textField: LocationTextField) -> Bool {
        guard let text = textField.text else { return true }
        if !text.trimmingCharacters(in: .whitespaces).isEmpty {
            delegate?.locationViewDidSubmitText(text)
            _ = textField.resignFirstResponder()
            return true
        } else {
            return false
        }
    }

    func locationTextFieldShouldClear(_ textField: LocationTextField) -> Bool {
        delegate?.locationViewDidClearText()
        return true
    }

    func locationTextFieldDidBeginEditing(_ textField: UITextField) {
        guard !isEditing else { return }
        updateUIForSearchEngineDisplay()
        let searchText = searchTerm != nil ? searchTerm : urlAbsolutePath

        // `attributedText` property is set to nil to remove all formatting and truncation set before.
        textField.attributedText = nil
        textField.text = searchText

        delegate?.locationViewDidBeginEditing(searchText ?? "", shouldShowSuggestions: searchTerm != nil)
    }

    func locationTextFieldDidEndEditing(_ textField: UITextField) {
        formatAndTruncateURLTextField()
        if isURLTextFieldEmpty {
            updateGradient()
        } else {
            updateUIForLockIconDisplay()
        }
    }

    // MARK: - Accessibility
    private func configureA11y(_ state: LocationViewState) {
        lockIconButton.accessibilityIdentifier = state.lockIconButtonA11yId
        lockIconButton.accessibilityLabel = state.lockIconButtonA11yLabel

        urlTextField.accessibilityIdentifier = state.urlTextFieldA11yId
        urlTextField.accessibilityLabel = state.urlTextFieldA11yLabel
    }

    func accessibilityCustomActionsForView(_ view: UIView) -> [UIAccessibilityCustomAction]? {
        guard view === urlTextField else { return nil }
        return delegate?.locationViewAccessibilityActions()
    }

    // MARK: - ThemeApplicable
    func applyTheme(theme: Theme) {
        let colors = theme.colors
        urlTextFieldColor = colors.textPrimary
        urlTextFieldSubdomainColor = colors.textSecondary
        gradientLayer.colors = colors.layerGradientURL.cgColors.reversed()
        searchEngineContentView.applyTheme(theme: theme)
        iconContainerBackgroundView.backgroundColor = colors.layerSearch
        lockIconButton.tintColor = colors.iconPrimary
        lockIconButton.backgroundColor = colors.layerSearch
        urlTextField.applyTheme(theme: theme)
    }
}
