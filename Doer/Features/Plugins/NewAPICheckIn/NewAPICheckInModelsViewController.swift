import UIKit

/// 「查看模型」— lists the models this account can use on the site
/// (`GET /api/user/models` with the stored session credential).
/// Tap a row to copy the model name; the toolbar copies the whole list.
@MainActor
final class NewAPICheckInModelsViewController: UIViewController {
    private let platform: NewAPICheckInPlatform
    private let store: NewAPICheckInStore
    private let service: NewAPICheckInService

    private var models: [String] = []
    private var statusMessage: String?
    private var isLoading = false

    private let tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .insetGrouped)
        table.register(UITableViewCell.self, forCellReuseIdentifier: "model")
        table.rowHeight = 44
        table.translatesAutoresizingMaskIntoConstraints = false
        return table
    }()

    private let statusLabel: UILabel = {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .footnote)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.isHidden = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let activityIndicator = UIActivityIndicatorView(style: .medium)

    private let refreshControl = UIRefreshControl()

    private lazy var copyAllButton: UIBarButtonItem = {
        let button = UIBarButtonItem(
            image: UIImage(systemName: "doc.on.doc"),
            style: .plain,
            target: self,
            action: #selector(copyAllTapped)
        )
        button.accessibilityLabel = String(localized: "plugins.newapi.models.copy_all", defaultValue: "复制全部模型")
        return button
    }()

    init(
        platform: NewAPICheckInPlatform,
        store: NewAPICheckInStore,
        service: NewAPICheckInService
    ) {
        self.platform = platform
        self.store = store
        self.service = service
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        title = String(localized: "plugins.newapi.models.title", defaultValue: "可用模型")

        view.addSubview(tableView)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = .systemGroupedBackground

        view.addSubview(statusLabel)
        activityIndicator.hidesWhenStopped = true
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(activityIndicator)

        navigationItem.rightBarButtonItem = copyAllButton
        copyAllButton.isEnabled = false
        refreshControl.addTarget(self, action: #selector(refreshTriggered), for: .valueChanged)
        tableView.refreshControl = refreshControl
        // Error / unsupported states hide the table, so the status label is
        // the fallback tap target for retrying.
        statusLabel.isUserInteractionEnabled = true
        statusLabel.addGestureRecognizer(UITapGestureRecognizer(
            target: self,
            action: #selector(refreshTriggered)
        ))

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            statusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32),

            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])

        Task { await loadModels() }
    }

    @objc private func refreshTriggered() {
        Task { await loadModels(force: true) }
    }

    private func loadModels(force: Bool = false) async {
        guard !isLoading else {
            // A load is already in flight; don't run a second one against the
            // same shared UI state. Pull-to-refresh just stops spinning.
            if force { refreshControl.endRefreshing() }
            return
        }
        isLoading = true
        statusLabel.isHidden = true
        tableView.isHidden = models.isEmpty
        activityIndicator.startAnimating()

        let result = await service.fetchAvailableModels(platform)

        isLoading = false
        activityIndicator.stopAnimating()
        refreshControl.endRefreshing()
        if result.models.isEmpty {
            models = []
            statusMessage = result.message ?? String(
                localized: "plugins.newapi.models.empty",
                defaultValue: "暂无可用模型"
            )
            statusLabel.text = statusMessage
            statusLabel.isHidden = false
            tableView.isHidden = true
        } else {
            models = result.models
            statusLabel.isHidden = true
            tableView.isHidden = false
        }
        title = models.isEmpty
            ? String(localized: "plugins.newapi.models.title", defaultValue: "可用模型")
            : String(format: String(localized: "plugins.newapi.models.title_count", defaultValue: "可用模型 · %d"), models.count)
        copyAllButton.isEnabled = !models.isEmpty
        tableView.reloadData()
    }

    @objc private func copyAllTapped() {
        guard !models.isEmpty else { return }
        UIPasteboard.general.string = models.joined(separator: "\n")
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        DoerFeedback.presentToast(
            String(
                format: String(localized: "plugins.newapi.models.copied_all", defaultValue: "已复制 %d 个模型"),
                models.count
            ),
            on: self
        )
    }
}

extension NewAPICheckInModelsViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        models.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "model", for: indexPath)
        var content = cell.defaultContentConfiguration()
        let model = models[indexPath.row]
        content.text = model
        content.textProperties.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        content.textProperties.color = .label
        cell.contentConfiguration = content
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        UIPasteboard.general.string = models[indexPath.row]
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        DoerFeedback.presentToast(
            String(localized: "plugins.newapi.models.copied", defaultValue: "模型名已复制"),
            on: self
        )
    }
}
