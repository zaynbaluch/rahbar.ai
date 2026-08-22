/// GBNF grammar that forces the exact MCQ schema `McqParser` expects: ten blocks
/// of `Qn [difficulty]` + stem + four options + `ANSWER: X`, then a `KEY:` line.
///
/// Why: the on-device bake-off (see docs/decisions/ADR-003) showed the fast LFM2
/// models generate good, grounded questions but drop the format — missing
/// difficulty tags, short of ten questions, or no ANSWER line — which breaks the
/// OMR key the app rebuilds from those ANSWER lines. Constraining *decoding* makes
/// schema-adherence a property of the sampler, not the model, so we keep LFM2's
/// ~2× speed AND get 10/10 parseable, OMR-ready questions every time.
///
/// Applied only to MCQ generation; lesson plans run unconstrained (free prose).
/// The grammar's own `KEY:` line can disagree with the per-question ANSWER lines
/// (they're decoded independently) — harmless, since `McqParser` derives the key
/// from the ANSWER lines and ignores the model's KEY line.
const String kMcqGrammarRoot = 'root';

const String kMcqGrammar = r'''
root ::= block1 block2 block3 block4 block5 block6 block7 block8 block9 block10 key
block1 ::= "Q1 [" diff "]\n" text "\n" "A) " text "\n" "B) " text "\n" "C) " text "\n" "D) " text "\n" "ANSWER: " letter "\n\n"
block2 ::= "Q2 [" diff "]\n" text "\n" "A) " text "\n" "B) " text "\n" "C) " text "\n" "D) " text "\n" "ANSWER: " letter "\n\n"
block3 ::= "Q3 [" diff "]\n" text "\n" "A) " text "\n" "B) " text "\n" "C) " text "\n" "D) " text "\n" "ANSWER: " letter "\n\n"
block4 ::= "Q4 [" diff "]\n" text "\n" "A) " text "\n" "B) " text "\n" "C) " text "\n" "D) " text "\n" "ANSWER: " letter "\n\n"
block5 ::= "Q5 [" diff "]\n" text "\n" "A) " text "\n" "B) " text "\n" "C) " text "\n" "D) " text "\n" "ANSWER: " letter "\n\n"
block6 ::= "Q6 [" diff "]\n" text "\n" "A) " text "\n" "B) " text "\n" "C) " text "\n" "D) " text "\n" "ANSWER: " letter "\n\n"
block7 ::= "Q7 [" diff "]\n" text "\n" "A) " text "\n" "B) " text "\n" "C) " text "\n" "D) " text "\n" "ANSWER: " letter "\n\n"
block8 ::= "Q8 [" diff "]\n" text "\n" "A) " text "\n" "B) " text "\n" "C) " text "\n" "D) " text "\n" "ANSWER: " letter "\n\n"
block9 ::= "Q9 [" diff "]\n" text "\n" "A) " text "\n" "B) " text "\n" "C) " text "\n" "D) " text "\n" "ANSWER: " letter "\n\n"
block10 ::= "Q10 [" diff "]\n" text "\n" "A) " text "\n" "B) " text "\n" "C) " text "\n" "D) " text "\n" "ANSWER: " letter "\n\n"
key ::= "KEY:" " 1=" letter " 2=" letter " 3=" letter " 4=" letter " 5=" letter " 6=" letter " 7=" letter " 8=" letter " 9=" letter " 10=" letter "\n"
diff ::= "easy" | "medium" | "hard"
letter ::= "A" | "B" | "C" | "D"
text ::= char char{0,199}
char ::= [^\n]
''';
