//
//  RuleConfigurationView.swift
//  FileFlow
//
//  Created by AutoAgent on 2025/12/23.
//

import SwiftUI

struct RuleConfigurationView: View {
    @State private var rules: [AutoRule] = []
    @State private var showingEditor = false
    @State private var editingRule: AutoRule?
    
    var body: some View {
        VStack {
            List {
                ForEach($rules) { $rule in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(rule.name)
                                .font(.headline)
                            Text("\(rule.conditions.count) 个条件, \(rule.actions.count) 个动作")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Toggle("", isOn: $rule.isEnabled)
                            .onChange(of: rule.isEnabled) { _, _ in
                                save(rule)
                            }
                            .labelsHidden()
                        
                        Button(action: { editingRule = rule }) {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 4)
                }
                .onDelete(perform: deleteRules)
            }
            // Add a footer with "Add" button if list is empty or for easier access?
            // Standard macOS UI puts add/remove at bottom of list or in toolbar.
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: {
                    runRulesNow()
                }) {
                    Label("立即运行", systemImage: "play.fill")
                }
            }
            
            ToolbarItem(placement: .primaryAction) {
                Button(action: {
                    editingRule = AutoRule(name: "新规则")
                }) {
                    Label("添加规则", systemImage: "plus")
                }
            }
        }
        .sheet(item: $editingRule) { rule in
            RuleEditorView(rule: rule, onSave: { updatedRule in
                save(updatedRule)
                loadRules()
                editingRule = nil
            }, onCancel: {
                editingRule = nil
            })
        }
        .onAppear {
            loadRules()
        }
    }
    
    private func loadRules() {
        Task {
            rules = await DatabaseManager.shared.getAllRules()
        }
    }
    
    private func save(_ rule: AutoRule) {
        Task {
            await DatabaseManager.shared.saveRule(rule)
        }
    }
    
    private func deleteRules(at offsets: IndexSet) {
        offsets.forEach { index in
            let rule = rules[index]
            Task {
                await DatabaseManager.shared.deleteRule(rule.id)
                loadRules()
            }
        }
    }
    
    private func runRulesNow() {
        Task {
            let files = await DatabaseManager.shared.getRecentFiles(limit: AppConstants.Rules.batchProcessLimit)
            for file in files {
                await RuleEngine.shared.applyRules(to: file)
            }
        }
    }
}

struct RuleEditorView: View {
    @State var rule: AutoRule
    var onSave: (AutoRule) -> Void
    var onCancel: () -> Void
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("基本信息")) {
                    TextField("规则名称", text: $rule.name)
                    Picker("匹配方式", selection: $rule.matchType) {
                        ForEach(RuleMatchType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                }
                
                Section(header: Text("条件")) {
                    ForEach($rule.conditions) { $condition in
                        HStack {
                            Picker("", selection: $condition.field) {
                                ForEach(RuleConditionField.allCases, id: \.self) { field in
                                    Text(field.rawValue).tag(field)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 120)
                            
                            Picker("", selection: $condition.operator) {
                                ForEach(RuleOperator.allCases, id: \.self) { op in
                                    Text(op.rawValue).tag(op)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 100)
                            
                            TextField("值", text: $condition.value)
                        }
                    }
                    .onDelete { indexSet in
                        rule.conditions.remove(atOffsets: indexSet)
                    }
                    
                    Button("添加条件") {
                        rule.conditions.append(RuleCondition(field: .fileName, operator: .contains, value: ""))
                    }
                }
                
                Section(header: Text("执行动作")) {
                    ForEach($rule.actions) { $action in
                        HStack {
                            Picker("", selection: $action.type) {
                                ForEach(RuleActionType.allCases, id: \.self) { type in
                                    Text(type.rawValue).tag(type)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 140)
                            
                            if action.type == .move {
                                TextField("分类 (例如: Projects/New)", text: $action.targetValue)
                            } else if action.type == .addTag {
                                TextField("标签名称", text: $action.targetValue)
                            } else {
                                Text("文件将被删除")
                                    .foregroundColor(.red)
                            }
                        }
                    }
                    .onDelete { indexSet in
                        rule.actions.remove(atOffsets: indexSet)
                    }
                    
                    Button("添加动作") {
                        rule.actions.append(RuleAction(type: .addTag, targetValue: ""))
                    }
                }
            }
            .navigationTitle("编辑规则")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(rule)
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 600, minHeight: 500)
        #endif
    }
}
