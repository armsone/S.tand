import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private let addressLabel = UILabel()
    private let statusLabel = UILabel()
    private let saveButton = UIButton(type: .system)
    private var configuration: InternetRadioConfiguration?

    override func viewDidLoad() {
        super.viewDidLoad()
        configureView()
        loadSharedURL()
    }

    private func configureView() {
        view.backgroundColor = .systemBackground

        let iconView = UIImageView(image: UIImage(systemName: "radio.fill"))
        iconView.tintColor = .systemOrange
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 42),
            iconView.heightAnchor.constraint(equalToConstant: 42)
        ])

        let titleLabel = UILabel()
        titleLabel.text = "S.tand 라디오에 추가"
        titleLabel.font = .preferredFont(forTextStyle: .title2).withWeight(.semibold)
        titleLabel.textAlignment = .center

        addressLabel.text = "공유 주소를 확인하는 중…"
        addressLabel.font = .preferredFont(forTextStyle: .footnote)
        addressLabel.textColor = .secondaryLabel
        addressLabel.textAlignment = .center
        addressLabel.numberOfLines = 0
        addressLabel.lineBreakMode = .byCharWrapping
        addressLabel.adjustsFontForContentSizeCategory = true

        let explanationLabel = UILabel()
        explanationLabel.text = "Safari에서 라디오가 직접 재생되는 HTTP 또는 HTTPS 주소만 저장해 주세요. HTTP 주소는 암호화되지 않으며, 일반 웹페이지 주소는 재생되지 않을 수 있습니다."
        explanationLabel.font = .preferredFont(forTextStyle: .footnote)
        explanationLabel.textColor = .secondaryLabel
        explanationLabel.textAlignment = .center
        explanationLabel.numberOfLines = 0
        explanationLabel.adjustsFontForContentSizeCategory = true

        statusLabel.font = .preferredFont(forTextStyle: .footnote).withWeight(.semibold)
        statusLabel.textColor = .systemOrange
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.adjustsFontForContentSizeCategory = true

        var saveConfiguration = UIButton.Configuration.filled()
        saveConfiguration.title = "라디오 주소로 가져오기"
        saveConfiguration.baseBackgroundColor = .systemOrange
        saveConfiguration.baseForegroundColor = .white
        saveConfiguration.cornerStyle = .large
        saveButton.configuration = saveConfiguration
        saveButton.isEnabled = false
        saveButton.addTarget(self, action: #selector(saveAddress), for: .touchUpInside)

        var cancelConfiguration = UIButton.Configuration.plain()
        cancelConfiguration.title = "취소"
        cancelConfiguration.baseForegroundColor = .secondaryLabel
        let cancelButton = UIButton(configuration: cancelConfiguration)
        cancelButton.addTarget(self, action: #selector(cancel), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [
            iconView,
            titleLabel,
            addressLabel,
            explanationLabel,
            statusLabel,
            saveButton,
            cancelButton
        ])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 14
        stack.setCustomSpacing(20, after: statusLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = UIScrollView()
        scrollView.alwaysBounceVertical = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        scrollView.addSubview(stack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -24),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -48),
            saveButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 50)
        ])
    }

    private func loadSharedURL() {
        let extensionItems = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        for extensionItem in extensionItems {
            let suggestedName = extensionItem.attributedTitle?.string ?? ""
            for provider in extensionItem.attachments ?? []
                where provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) {
                    [weak self] item, error in
                    DispatchQueue.main.async {
                        self?.applyLoadedItem(item, suggestedName: suggestedName, error: error)
                    }
                }
                return
            }
        }
        showLoadFailure("공유된 웹 주소를 찾을 수 없습니다.")
    }

    private func applyLoadedItem(_ item: NSSecureCoding?, suggestedName: String, error: Error?) {
        guard error == nil else {
            showLoadFailure("공유 주소를 읽지 못했습니다.")
            return
        }

        let url: URL?
        if let sharedURL = item as? URL {
            url = sharedURL
        } else if let sharedURL = item as? NSURL {
            url = sharedURL as URL
        } else if let sharedText = item as? String {
            url = URL(string: sharedText)
        } else {
            url = nil
        }

        guard let url else {
            showLoadFailure("공유된 웹 주소를 찾을 수 없습니다.")
            return
        }

        addressLabel.text = url.absoluteString
        do {
            configuration = try InternetRadioConfiguration(
                displayName: suggestedName,
                urlString: url.absoluteString
            )
            statusLabel.text = "S.tand를 열면 라디오 채널 입력란에 자동으로 채워집니다. 저장 전까지 기존 채널 목록은 바뀌지 않습니다."
            saveButton.isEnabled = true
        } catch {
            showLoadFailure(error.localizedDescription)
        }
    }

    private func showLoadFailure(_ message: String) {
        configuration = nil
        statusLabel.text = message
        saveButton.isEnabled = false
    }

    @objc private func saveAddress() {
        guard let configuration else { return }
        guard SharedInternetRadioImportStore().save(configuration) else {
            showLoadFailure("S.tand와 주소를 공유할 수 없습니다. 앱을 한 번 연 뒤 다시 시도해 주세요.")
            return
        }

        saveButton.isEnabled = false
        saveButton.configuration?.title = "가져옴"
        statusLabel.text = "S.tand를 열어 주소를 확인하고 저장해 주세요."
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
    }

    @objc private func cancel() {
        extensionContext?.cancelRequest(
            withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)
        )
    }
}

private extension UIFont {
    func withWeight(_ weight: UIFont.Weight) -> UIFont {
        let descriptor = fontDescriptor.addingAttributes([
            .traits: [UIFontDescriptor.TraitKey.weight: weight]
        ])
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}
