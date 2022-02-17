/*
 * Copyright (c) 2021-present, Trail of Bits, Inc.
 * All rights reserved.
 *
 * This source code is licensed in accordance with the terms specified in
 * the LICENSE file found in the root directory of this source tree.
 */

#pragma once

#include "rellic/AST/ASTPass.h"
#include "rellic/AST/IRToASTVisitor.h"
#include "rellic/AST/TransformVisitor.h"
#include "rellic/AST/Z3ConvVisitor.h"

namespace rellic {

/*
 * This pass converts a sequence of if statements shaped like
 *
 *   if(cond) {
 *     body_then;
 *   }
 *   if(!cond) {
 *     body_else;
 *   }
 *
 * into
 *
 *   if(cond) {
 *     body_then;
 *   } else {
 *     body_else;
 *   }
 */
class CondBasedRefine : public TransformVisitor<CondBasedRefine> {
 private:
  std::unique_ptr<z3::context> z3_ctx;
  std::unique_ptr<rellic::Z3ConvVisitor> z3_gen;

  z3::tactic z3_solver;

  z3::expr GetZ3Cond(clang::IfStmt *ifstmt);

  bool Prove(z3::expr expr);

  using IfStmtVec = std::vector<clang::IfStmt *>;

  void CreateIfThenElseStmts(IfStmtVec stmts);

 protected:
  void RunImpl() override;

 public:
  CondBasedRefine(StmtToIRMap &provenance, clang::ASTUnit &unit);

  bool VisitCompoundStmt(clang::CompoundStmt *compound);
};

}  // namespace rellic
