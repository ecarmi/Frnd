def enum_value(value) -> str | None:
    """Return the string value for enum-or-string ORM fields."""
    if value is None:
        return None
    return value.value if hasattr(value, "value") else str(value)


def enum_equals(value, expected) -> bool:
    """Compare enum-or-string ORM fields against enum-or-string constants."""
    return enum_value(value) == enum_value(expected)
