/*
 * Copyright (c) 2021-present, Trail of Bits, Inc.
 * All rights reserved.
 *
 * This source code is licensed in accordance with the terms specified in
 * the LICENSE file found in the root directory of this source tree.
 */

#pragma once

#include <llvm/IR/Module.h>
#include <llvm/Pass.h>

#include "rellic/AST/IRToASTVisitor.h"
#include "rellic/AST/TransformVisitor.h"

namespace rellic {

class LoopRefine : public llvm::ModulePass,
                   public TransformVisitor<LoopRefine> {
 private:
  clang::ASTUnit &unit;

 public:
  static char ID;

  LoopRefine(clang::ASTUnit &unit);

  bool VisitWhileStmt(clang::WhileStmt *loop);

  bool runOnModule(llvm::Module &module) override;
};

}  // namespace rellic