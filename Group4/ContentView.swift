import SwiftUI
import CoreHaptics

struct ContentView: View {
    @State private var engine: CHHapticEngine?
    @State private var currentBlock: (row: Int, col: Int)? = nil
    @State private var longPressTimer: Timer?
    @State private var longPressTriggered = false

    @State private var inputText: String = ""
    @State private var isShifted: Bool = false
    @State private var useHangulKeyboard: Bool = false

    // caps lock
    @State private var isCapsLock: Bool = false 
    @State private var shiftTapCount: Int = 0 
    @State private var lastShiftTapTime: Date? = nil 

    // consecutive deletion 
    @State private var backspaceTimer: Timer? 

    let rows = 7
    let cols = 5

    let baseBlockLabels: [String] = [
        "q", "w", "⌫", "o", "p",
        "a", "s", "⌫", "k", "l",
        "z", "x", "shift", "n", "m",
        "e", "r", "␣", "u", "i",
        "d", "f", "␣", "h", "j",
        "c", "v", "⏎", "b", "y",
        "t", "g", "⏎", ",", "?"
    ]

    // caps lock 
    var blockLabels: [String] {
        baseBlockLabels.map { label in
            if label.count == 1 && label.range(of: "[a-z]", options: .regularExpression) != nil {
                if isCapsLock || isShifted {
                    return label.uppercased()
                } else {
                    return label.lowercased()
                }
            } else if label == "shift" {
                return isCapsLock ? "capslock.fill" : (isShifted ? "shift.fill" : "shift")
            } else {
                return label
            }
        }
    }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button(action: {
                        useHangulKeyboard.toggle()
                    }) {
                        Text(useHangulKeyboard ? "ABC" : "한글")
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(8)
                    }
                    .padding()
                }

                TextView(text: $inputText)
                    .frame(height: 80)
                    .padding()
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.3)))

                Spacer()

                if useHangulKeyboard {
                    HangulKeyboardView(text: $inputText)
                        .frame(height: 260)
                } else {
                    VStack(spacing: 0) {
                        ForEach(0..<rows, id: \.self) { row in
                            HStack(spacing: 0) {
                                ForEach(0..<cols, id: \.self) { col in
                                    let idx = row * cols + col
                                    let label = blockLabels[idx]
                                    ZStack {
                                        Rectangle()
                                            .fill(self.colorFor(row: row, col: col))
                                            .frame(width: geo.size.width / CGFloat(cols),
                                                   height: geo.size.width / CGFloat(cols))
                                        if (label.count > 1) {
                                            Image(systemName: label)
                                                .resizable()
                                                .frame(width: 24, height: 24)
                                                .foregroundColor(.black)
                                        } else {
                                            Text(blockLabels[idx])
                                                .font(.system(size: 24))
                                                .foregroundColor(self.colorFor(row: row, col: col) == .black ? .white : .black)
                                        }
                                    }
                                    // consecutive deletion
                                   .simultaneousGesture(
                                        LongPressGesture(minimumDuration: 0.3)
                                        .onEnded { _ in
                                            if blockLabels[idx] == "⌫" {
                                                startBackspace()
                                            }
                                        }
                                    )
                                    .simultaneousGesture(
                                        DragGesture(minimumDistance: 0)
                                            .onEnded { _ in
                                                if blockLabels[idx] == "⌫" {
                                                    stopBackspace()
                                                }
                                            }
                                    )
                                }
                            }
                        }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let block = self.blockAt(location: value.location, in: geo.size)
                                if block?.row != self.currentBlock?.row || block?.col != self.currentBlock?.col {
                                    self.currentBlock = block
                                    self.longPressTriggered = false
                                    self.longPressTimer?.invalidate()
                                    if let block = block {
                                        self.prepareHaptics()
                                        self.playBlockHaptic(row: block.row, col: block.col)
                                    }
                                }
                            }
                            .onEnded { _ in
                                self.longPressTimer?.invalidate()
                                if let block = self.currentBlock {
                                    let feedback = UINotificationFeedbackGenerator()
                                    feedback.prepare()
                                    feedback.notificationOccurred(.success)
                                    self.handleKeyInput(row: block.row, col: block.col)
                                }
                                self.currentBlock = nil
                            }
                    )
                }
            }
        }
    }

    func blockAt(location: CGPoint, in size: CGSize) -> (row: Int, col: Int)? {
        let blockWidth = size.width / CGFloat(cols)
        let blockHeight = size.width / CGFloat(cols)
        let col = Int(location.x / blockWidth)
        let row = Int(location.y / blockHeight)
        guard row >= 0, row < rows, col >= 0, col < cols else { return nil }
        return (row, col)
    }

    func colorFor(row: Int, col: Int) -> Color {
        let idx = row * cols + col
        let label = blockLabels[idx]
        switch label {
        case "␣":
            return .yellow.opacity(0.7)
        case "⌫":
            return .red.opacity(0.7)
        case "shift":
            return .blue.opacity(0.7)
        case "shift.fill", "capslock.fill":
            return .blue.opacity(0.4)
        case "⏎":
            return .mint.opacity(0.7)
        default:
            return (row + col) % 2 == 0 ? .white : .black
        }
    }

    // Reuse your haptic and input logic here
    func prepareHaptics() {
        if engine == nil {
            do {
                engine = try CHHapticEngine()
                try engine?.start()
            } catch {
                print("Engine Start Error: \(error.localizedDescription)")
            }
        }
    }
    
    private func playHaptics(events: [CHHapticEvent]) {
        do {
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine?.makePlayer(with: pattern)
            try player?.start(atTime: 0)
        } catch {
            print("Failed to play haptic: \(error.localizedDescription)")
        }
    }

    func playBlockHaptic(row: Int, col: Int) {
        switch (row, col) {
        case (0,0): HapticManager.doHaptics_test_Q(engine: engine)
        case (0,1): HapticManager.doHaptics_test_W(engine: engine)
        case (0,2), (1,2): doHaptics_delete()
        case (0,3): HapticManager.doHaptics_03(engine: engine)
        case (0,4): HapticManager.doHaptics_04(engine: engine)
        case (1,0): HapticManager.doHaptics_test_A(engine: engine)
        case (1,1): HapticManager.doHaptics_test_S(engine: engine)
        case (1,3): HapticManager.doHaptics_13(engine: engine)
        case (1,4): HapticManager.doHaptics_14(engine: engine)
        case (2,0): HapticManager.doHaptics_test_Z(engine: engine)
        case (2,1): HapticManager.doHaptics_test_X(engine: engine)
        case (2,2): doHaptics_shift()
        case (2,3): HapticManager.doHaptics_23(engine: engine)
        case (2,4): HapticManager.doHaptics_24(engine: engine)
        case (3,0): HapticManager.doHaptics_test_E(engine: engine)
        case (3,1): HapticManager.doHaptics_test_R(engine: engine)
        case (3,2), (4,2): doHaptics_space()
        case (3,3): HapticManager.doHaptics_33(engine: engine)
        case (3,4): HapticManager.doHaptics_34(engine: engine)
        case (4,0): HapticManager.doHaptics_test_D(engine: engine)
        case (4,1): HapticManager.doHaptics_test_F(engine: engine)
        case (4,3): HapticManager.doHaptics_43(engine: engine)
        case (4,4): HapticManager.doHaptics_44(engine: engine)
        case (5,0): HapticManager.doHaptics_test_C(engine: engine)
        case (5,1): HapticManager.doHaptics_test_V(engine: engine)
        case (5,2), (6,2): doHaptics_return()
        case (5,3): HapticManager.doHaptics_53(engine: engine)
        case (5,4): HapticManager.doHaptics_54(engine: engine)
        case (6,0): HapticManager.doHaptics_test_T(engine: engine)
        case (6,1): HapticManager.doHaptics_test_G(engine: engine)
        case (6,3): HapticManager.doHaptics_63(engine: engine)
        case (6,4): HapticManager.doHaptics_64(engine: engine)
        default: print("Invalid input for haptic feedback: row \(row), col \(col)")
        }
    }
    
    func doHaptics_delete() {
        let feedback = UINotificationFeedbackGenerator()
        feedback.prepare()
        feedback.notificationOccurred(.error)
    }

    func doHaptics_shift() {
        let feedback = UISelectionFeedbackGenerator()
        feedback.prepare()
        feedback.selectionChanged()
        // caps lock
        let now = Date()
        if let lastTap = lastShiftTapTime, now.timeIntervalSince(lastTap) < 0.5 {
            shiftTapCount += 1
        } else {
            shiftTapCount = 1
        }
        lastShiftTapTime = now
        
        if shiftTapCount == 2 {
            isCapsLock.toggle()
            isShifted = isCapsLock // caps lock이 켜지면 대문자 유지
            shiftTapCount = 0
        } else {
            if isCapsLock {
                isCapsLock = false
            }
            isShifted.toggle()
        }
    }

    func doHaptics_space() {
        let feedback = UINotificationFeedbackGenerator()
        feedback.prepare()
        feedback.notificationOccurred(.success)
    }

    func doHaptics_return() {
        let feedback = UINotificationFeedbackGenerator()
        feedback.prepare()
        feedback.notificationOccurred(.warning)
    }

    // backspace timer 
    func startBackspace() {
        stopBackspace()
        backspaceTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { _ in
            if !inputText.isEmpty {
                inputText.removeLast()
            }
        }
    }
    func stopBackspace() {
        backspaceTimer?.invalidate()
        backspaceTimer = nil
    }

    func handleKeyInput(row: Int, col: Int) {
        let idx = row * cols + col
        guard idx < blockLabels.count else { return }
        let label = blockLabels[idx]
        switch label {
        case "␣":
            inputText.append(" ")
        case "⏎":
            inputText.append("\n")
        case "shift", "shift.fill", "capslock.fill":
            // shift/caps lock 상태는 doHaptics_shift에서 처리
            break
        case "⌫":
            if !inputText.isEmpty {
                inputText.removeLast()
            }
        case "":
            break
        default:
            inputText.append(label)
            // caps lock
            if isShifted && !isCapsLock && label.range(of: "[a-zA-Z]", options: .regularExpression) != nil {
                isShifted = false
            }
        }
    }
}

// UITextView wrapper that supports copy/paste without keyboard activation
struct TextView: UIViewRepresentable {
    @Binding var text: String

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.font = UIFont.systemFont(ofSize: 28)
        textView.backgroundColor = UIColor.clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.isScrollEnabled = true
        textView.inputView = UIView() // disables system keyboard
        textView.inputAccessoryView = UIView()
        textView.isSelectable = true
        textView.isEditable = true
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: TextView

        init(_ parent: TextView) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            return true
        }
    }
}



