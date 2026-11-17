import UIKit

final class ViewController: UIViewController {

    private var taps = 0

    private let titleLabel = UILabel()
    private let countLabel = UILabel()
    private let button = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white

        titleLabel.text = "Modern"
        titleLabel.font = .systemFont(ofSize: 44, weight: .bold)
        titleLabel.textAlignment = .center

        countLabel.text = "0 taps"
        countLabel.font = .systemFont(ofSize: 20, weight: .regular)
        countLabel.textColor = .darkGray
        countLabel.textAlignment = .center

        button.setTitle("Tap me", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 22, weight: .semibold)
        button.addTarget(self, action: #selector(didTap), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [titleLabel, countLabel, button])
        stack.axis = .vertical
        stack.spacing = 24
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    @objc private func didTap() {
        taps += 1
        countLabel.text = taps == 1 ? "1 tap" : "\(taps) taps"
    }
}
