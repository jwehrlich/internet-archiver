document.addEventListener('DOMContentLoaded', function () {
  const tbody = document.querySelector('tbody');

  function handleDragStart(e) {
    e.dataTransfer.effectAllowed = 'move';
    e.dataTransfer.setData('text/plain', this.innerHTML);
    this.classList.add('dragging');
  }

  function handleDragOver(e) {
    if (e.preventDefault) {
      e.preventDefault();
    }
    e.dataTransfer.dropEffect = 'move';
    return false;
  }

  function handleDragEnter(e) {
    this.classList.add('over');
  }

  function handleDragLeave() {
    this.classList.remove('over');
  }

  function handleDrop(e) {
    if (e.stopPropagation) {
      e.stopPropagation();
    }

    const draggedRow = document.querySelector('.dragging');
    const droppedRow = this;

    if (draggedRow !== droppedRow) {
      draggedRow.innerHTML = droppedRow.innerHTML;
      droppedRow.innerHTML = e.dataTransfer.getData('text/plain');

      // Update the priority on drop
      updatePriority();

      // Remove the 'over' class from the dropped row
      droppedRow.classList.remove('over');
    }

    return false;
  }

  function handleDragEnd() {
    this.classList.remove('dragging');
    // Update the priority when dragging ends
    updatePriority();
  }

  function updatePriority() {
    const rows = Array.from(tbody.querySelectorAll('tr'));
    rows.forEach((row, index) => {
      const priorityCell = row.querySelector('.priority');
      if (priorityCell) {
        priorityCell.textContent = index + 1;
      }

      // Update priority in the backend (you may need an AJAX request here)
      const contentId = row.querySelector('.content-id').textContent;
      const priority = index + 1;
      // Make an AJAX request to update the priority in the backend
      // Example using fetch:
      fetch(`/downloads/${contentId}/edit?priority=${priority}`, { method: 'PATCH' });
    });
  }

  const rows = document.querySelectorAll('tbody tr');
  rows.forEach(row => {
    row.setAttribute('draggable', 'true');
    row.addEventListener('dragstart', handleDragStart, false);
    row.addEventListener('dragenter', handleDragEnter, false);
    row.addEventListener('dragover', handleDragOver, false);
    row.addEventListener('dragleave', handleDragLeave, false);
    row.addEventListener('drop', handleDrop, false);
    row.addEventListener('dragend', handleDragEnd, false);
  });
});
