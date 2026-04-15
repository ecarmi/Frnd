import enum

from sqlalchemy import String
from sqlalchemy.types import TypeDecorator


class EnumString(TypeDecorator):
    """Persist enums as strings while returning enum instances from the ORM."""

    impl = String
    cache_ok = True

    def __init__(self, enum_cls: type[enum.Enum], length: int | None = None):
        self.enum_cls = enum_cls
        self.length = length or max(len(member.value) for member in enum_cls)
        super().__init__()

    def load_dialect_impl(self, dialect):
        return dialect.type_descriptor(String(self.length))

    def process_bind_param(self, value, dialect):
        if value is None:
            return None
        if isinstance(value, self.enum_cls):
            return value.value
        if isinstance(value, str):
            try:
                return self.enum_cls(value).value
            except ValueError:
                return value
        raise TypeError(f"Expected {self.enum_cls.__name__} or str, got {type(value).__name__}")

    def process_result_value(self, value, dialect):
        if value is None:
            return None
        try:
            return self.enum_cls(value)
        except ValueError:
            return value
