public with sharing class FormulaEvaluator {
    
    public class FormulaEvaluatorException extends Exception {}
    
    /* ===================== PUBLIC API ===================== */
    
    public static Decimal evaluate(String formula, Unit__c unit) {
        if (String.isBlank(formula)) return 0;
        if (unit == null) throw new FormulaEvaluatorException('Unit record is null');
        
        Map<String, Schema.SObjectField> fieldMap =
            Unit__c.SObjectType.getDescribe().fields.getMap();
        
        List<Token> tokens = tokenize(formula);
        
        // Replace field identifiers with values
        for (Token t : tokens) {
            if (t.type == TokenType.IDENTIFIER && fieldMap.containsKey(t.value)) {
                t.type = TokenType.NUM;
                t.value = String.valueOf(coerceToDecimal(unit.get(t.value)));
            }
        }
        
        List<Token> rpn = toRPN(tokens);
        return evalRPN(rpn);
    }
    
    /* ===================== TOKEN ===================== */
    
    private enum TokenType {
        NUM, OPERATOR, IDENTIFIER, FUNCTION, LPAREN, RPAREN, COMMA
            }
    
    private class Token {
        TokenType type;
        String value;
        Token(TokenType t, String v) {
            type = t;
            value = v;
        }
    }
    
    /* ===================== TOKENIZER ===================== */
    
    private static List<Token> tokenize(String expr) {
        expr = expr.replaceAll('\\s+', '');
        List<Token> tokens = new List<Token>();
        Integer i = 0;
        
        while (i < expr.length()) {
            String ch = expr.substring(i, i + 1);
            
            // Number (supports unary minus and %)
            if (isDigit(ch) || ch == '.' || (ch == '-' && isUnary(expr, i))) {
                Integer start = i++;
                while (i < expr.length() &&
                       (isDigit(expr.substring(i, i + 1)) || expr.substring(i, i + 1) == '.')) {
                           i++;
                       }
                
                Decimal num = Decimal.valueOf(expr.substring(start, i));
                
                if (i < expr.length() && expr.substring(i, i + 1) == '%') {
                    num = num / 100;
                    i++;
                }
                
                tokens.add(new Token(TokenType.NUM, String.valueOf(num)));
                continue;
            }
            
            // Identifier / Function
            if (isAlpha(ch)) {
                Integer start = i++;
                while (i < expr.length() && isAlphaNum(expr.substring(i, i + 1))) i++;
                String name = expr.substring(start, i);
                
                if (i < expr.length() && expr.substring(i, i + 1) == '(')
                    tokens.add(new Token(TokenType.FUNCTION, name.toUpperCase()));
                else
                    tokens.add(new Token(TokenType.IDENTIFIER, name));
                
                continue;
            }
            
            if (ch == '(') tokens.add(new Token(TokenType.LPAREN, ch));
            else if (ch == ')') tokens.add(new Token(TokenType.RPAREN, ch));
            else if (ch == ',') tokens.add(new Token(TokenType.COMMA, ch));
            else if ('+-*/'.contains(ch)) tokens.add(new Token(TokenType.OPERATOR, ch));
            else throw new FormulaEvaluatorException('Invalid character: ' + ch);
            
            i++;
        }
        return tokens;
    }
    
    /* ===================== SHUNTING YARD ===================== */
    
    private static List<Token> toRPN(List<Token> tokens) {
        List<Token> output = new List<Token>();
        List<Token> stack = new List<Token>();
        
        for (Token t : tokens) {
            
            if (t.type == TokenType.NUM) {
                output.add(t);
            }
            else if (t.type == TokenType.FUNCTION) {
                stack.add(t);
            }
            else if (t.type == TokenType.OPERATOR) {
                while (!stack.isEmpty() &&
                       stack[stack.size() - 1].type == TokenType.OPERATOR &&
                       precedence(stack[stack.size() - 1].value) >= precedence(t.value)) {
                           
                           output.add(stack.remove(stack.size() - 1));
                       }
                stack.add(t);
            }
            else if (t.type == TokenType.LPAREN) {
                stack.add(t);
            }
            else if (t.type == TokenType.RPAREN) {
                while (!stack.isEmpty() && stack[stack.size() - 1].type != TokenType.LPAREN) {
                    output.add(stack.remove(stack.size() - 1));
                }
                stack.remove(stack.size() - 1); // remove '('
                
                if (!stack.isEmpty() && stack[stack.size() - 1].type == TokenType.FUNCTION) {
                    output.add(stack.remove(stack.size() - 1));
                }
            }
        }
        
        while (!stack.isEmpty()) {
            output.add(stack.remove(stack.size() - 1));
        }
        
        return output;
    }
    
    /* ===================== RPN EVALUATOR ===================== */
    
    private static Decimal evalRPN(List<Token> rpn) {
        List<Decimal> stack = new List<Decimal>();
        
        for (Token t : rpn) {
            if (t.type == TokenType.NUM) {
                stack.add(Decimal.valueOf(t.value));
            }
            else if (t.type == TokenType.OPERATOR) {
                if (stack.size() < 2) throw new FormulaEvaluatorException('Invalid formula format near operator ' + t.value);
                
                Decimal b = stack.remove(stack.size() - 1);
                Decimal a = stack.remove(stack.size() - 1);
                
                if (t.value == '+') stack.add(a + b);
                else if (t.value == '-') stack.add(a - b);
                else if (t.value == '*') stack.add(a * b);
                else if (t.value == '/') {
                    // For validation, we don't care about div by zero, just structure. 
                    // But if checking logic, b==0 is an error.
                    if (b == 0) stack.add(0); // Prevent crash during validation with dummy data
                    else stack.add(a / b);
                }
            }
            else if (t.type == TokenType.FUNCTION) {
                stack.add(applyFunction(t.value, stack));
            }
        }
        
        if (stack.size() != 1) {
            throw new FormulaEvaluatorException('Incomplete expression. Check operators and operands.');
        }
        
        return stack[0];
    }
    
    /* ===================== FUNCTIONS ===================== */
    
    private static Decimal applyFunction(String fn, List<Decimal> s) {
        if (fn == 'ABS') return Math.abs(s.remove(s.size() - 1));
        if (fn == 'CEIL') return s.remove(s.size() - 1).setScale(0, RoundingMode.CEILING);
        if (fn == 'FLOOR') return s.remove(s.size() - 1).setScale(0, RoundingMode.FLOOR);
        
        if (fn == 'ROUND') {
            Integer scale = Integer.valueOf(s.remove(s.size() - 1));
            return s.remove(s.size() - 1).setScale(scale, RoundingMode.HALF_UP);
        }
        
        if (fn == 'MIN') {
            Decimal b = s.remove(s.size() - 1);
            Decimal a = s.remove(s.size() - 1);
            return a < b ? a : b;
        }
        
        if (fn == 'MAX') {
            Decimal b = s.remove(s.size() - 1);
            Decimal a = s.remove(s.size() - 1);
            return a > b ? a : b;
        }
        
        if (fn == 'POWER') {
            Decimal b = s.remove(s.size() - 1);
            Decimal a = s.remove(s.size() - 1);
            return Decimal.valueOf(Math.pow(Double.valueOf(a), Double.valueOf(b)));
        }
        
        throw new FormulaEvaluatorException('Unsupported function: ' + fn);
    }
    
    /* ===================== HELPERS ===================== */
    
    private static Boolean isDigit(String c) { return c >= '0' && c <= '9'; }
    private static Boolean isAlpha(String c) { return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || c == '_'; }
    private static Boolean isAlphaNum(String c) { return isAlpha(c) || isDigit(c); }
    
    private static Boolean isUnary(String expr, Integer i) {
        return i == 0 || '+-*/('.contains(expr.substring(i - 1, i));
    }
    
    private static Integer precedence(String op) {
        if (op == '*' || op == '/') return 2;
        if (op == '+' || op == '-') return 1;
        return 0;
    }
    
    private static Decimal coerceToDecimal(Object o) {
        if (o == null) return 0;
        if (o instanceof Decimal) return (Decimal)o;
        if (o instanceof Integer) return Decimal.valueOf((Integer)o);
        if (o instanceof Long) return Decimal.valueOf((Long)o);
        if (o instanceof Double) return Decimal.valueOf(o + '');
        if (o instanceof String && !String.isBlank((String)o))
            return Decimal.valueOf((String)o);
        return 0;
    }
    
    /* ===================== VALIDATION API ===================== */
    
    /**
    * Validates the formula structure and field references.
    * Returns 'VALID' if correct, or an error message string if invalid.
    */
    public static String validate(String formula) {
        if (String.isBlank(formula)) return 'Formula cannot be empty';
        
        try {
            // 1. Parse tokens
            List<Token> tokens = tokenize(formula);
            if (tokens.isEmpty()) return 'Formula contains no valid logic';
            
            // 2. Validate Fields and Substitute Dummy Data
            Map<String, Schema.SObjectField> fieldMap =
                Unit__c.SObjectType.getDescribe().fields.getMap();
            
            Integer openParens = 0;
            Integer closedParens = 0;
            
            for (Token t : tokens) {
                // Count parentheses manually to catch mismatches early
                if (t.type == TokenType.LPAREN) openParens++;
                if (t.type == TokenType.RPAREN) closedParens++;
                
                // If it's a field name, check if it exists
                if (t.type == TokenType.IDENTIFIER) {
                    if (!fieldMap.containsKey(t.value)) {
                        throw new FormulaEvaluatorException('Invalid Field API Name: ' + t.value);
                    }
                    
                    Schema.DescribeFieldResult d = fieldMap.get(t.value).getDescribe();
                    if (d.getType() != Schema.DisplayType.Double &&
                        d.getType() != Schema.DisplayType.Integer &&
                        d.getType() != Schema.DisplayType.Currency &&
                        d.getType() != Schema.DisplayType.Percent) {
                            
                            throw new FormulaEvaluatorException('Field ' + t.value + ' is not a numeric type.');
                        }
                    
                    // Replace field with dummy number '1' to test math structure
                    t.type = TokenType.NUM;
                    t.value = '1'; 
                }
            }
            
            if (openParens != closedParens) {
                throw new FormulaEvaluatorException('Mismatched Parentheses: Opened ' + openParens + ', Closed ' + closedParens);
            }
            
            // 3. Convert to RPN (Checks order of operations)
            List<Token> rpn = toRPN(tokens);
            
            // 4. Evaluate with Dummy Data (Checks function argument counts)
            Decimal result = evalRPN(rpn);
            
            return 'VALID';
            
        } catch (Exception e) {
            return 'Error: ' + e.getMessage();
        }
    }
}