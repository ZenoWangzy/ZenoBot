"""简单计算器模块

提供基本的四则运算功能：加法、减法、乘法和除法。
"""


def greeting(name: str = "世界") -> str:
    """返回问候语。

    Args:
        name: 要问候的名字，默认为 "世界"

    Returns:
        格式化的问候字符串
    """
    return f"你好，{name}"


def add(a: float, b: float) -> float:
    """返回两个数的和。

    Args:
        a: 第一个加数
        b: 第二个加数

    Returns:
        a 和 b 的和
    """
    return a + b


def subtract(a: float, b: float) -> float:
    """返回两个数的差。

    Args:
        a: 被减数
        b: 减数

    Returns:
        a 减去 b 的差
    """
    return a - b


def multiply(a: float, b: float) -> float:
    """返回两个数的积。

    Args:
        a: 第一个因数
        b: 第二个因数

    Returns:
        a 和 b 的乘积
    """
    return a * b


def divide(a: float, b: float) -> float:
    """返回两个数的商。

    Args:
        a: 被除数
        b: 除数

    Returns:
        a 除以 b 的商

    Raises:
        ZeroDivisionError: 当除数 b 为 0 时抛出
    """
    if b == 0:
        raise ZeroDivisionError("除数不能为零")
    return a / b


def main():
    """交互式计算器主函数。"""
    print("=== 简单计算器 ===")
    print("支持的操作：+ - * /")

    while True:
        print("\n请输入表达式（例如: 1 + 2），或输入 'q' 退出:")
        user_input = input("> ").strip()

        if user_input.lower() == 'q':
            print("再见！")
            break

        try:
            parts = user_input.split()
            if len(parts) != 3:
                print("错误：请按照 '数字 运算符 数字' 的格式输入")
                continue

            a = float(parts[0])
            op = parts[1]
            b = float(parts[2])

            if op == '+':
                result = add(a, b)
            elif op == '-':
                result = subtract(a, b)
            elif op == '*':
                result = multiply(a, b)
            elif op == '/':
                result = divide(a, b)
            else:
                print(f"错误：不支持的运算符 '{op}'")
                continue

            print(f"结果: {result}")

        except ValueError:
            print("错误：请输入有效的数字")
        except ZeroDivisionError as e:
            print(f"错误: {e}")


if __name__ == "__main__":
    main()
