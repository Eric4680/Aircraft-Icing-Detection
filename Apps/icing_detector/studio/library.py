from PySide6.QtCore import QAbstractListModel, QModelIndex, Qt, Signal, Property


class LibraryModel(QAbstractListModel):
    countChanged = Signal()
    FIELDS = ("imageId", "name", "thumbnail", "pixelWidth", "pixelHeight", "status", "error")

    def __init__(self, parent=None):
        super().__init__(parent)
        self.entries = []

    def roleNames(self):
        return {Qt.ItemDataRole.UserRole + index + 1: field.encode()
                for index, field in enumerate(self.FIELDS)}

    def rowCount(self, parent=QModelIndex()):
        return len(self.entries) if not parent.isValid() else 0

    def data(self, index, role):
        field_index = role - Qt.ItemDataRole.UserRole - 1
        if index.isValid() and 0 <= index.row() < len(self.entries) and 0 <= field_index < len(self.FIELDS):
            field = self.FIELDS[field_index]
            field = {"pixelWidth": "width", "pixelHeight": "height"}.get(field, field)
            return self.entries[index.row()].get(field, "")
        return None

    @Property(int, notify=countChanged)
    def count(self):
        return len(self.entries)

    def append(self, entry):
        row = len(self.entries)
        self.beginInsertRows(QModelIndex(), row, row)
        self.entries.append(entry)
        self.endInsertRows()
        self.countChanged.emit()

    def remove(self, row):
        self.beginRemoveRows(QModelIndex(), row, row)
        self.entries.pop(row)
        self.endRemoveRows()
        self.countChanged.emit()

    def changed(self, entry):
        row = self.entries.index(entry)
        self.dataChanged.emit(self.index(row), self.index(row), list(self.roleNames()))
