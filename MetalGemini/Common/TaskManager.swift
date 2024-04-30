//
//  TaskManager.swift
//  MetalGemini
//
//  Created by Bill Doughty on 4/29/24.
//

import Foundation

class TaskManager {
    private var queue = DispatchQueue(label: "com.example.myqueue")
    private var tasksCount = 0
    private let lock = NSLock()

    func addTask(_ task: @escaping () -> Void) {
        lock.lock()
        tasksCount += 1
        lock.unlock()

        queue.async {
            task()
            self.taskCompleted()
        }
    }

    private func taskCompleted() {
        lock.lock()
        tasksCount -= 1
        lock.unlock()
    }

    func pendingTasksCount() -> Int {
        lock.lock()
        let count = tasksCount
        lock.unlock()
        return count
    }
}
