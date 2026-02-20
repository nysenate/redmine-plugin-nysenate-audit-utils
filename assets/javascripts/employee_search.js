// Global state for cleanup
let employeeSearchState = {
  initialized: false,
  listeners: [],
  searchTimeout: null,
  currentRequest: null,
  fieldMappings: null,
  currentSearchQuery: '',
  currentOffset: 0,
  hasMore: false,
  isLoadingMore: false
};

function initializeEmployeeSearch() {
  const searchWidget = document.getElementById('employee-search-widget');
  const searchInput = document.getElementById('employee-search-input');
  const resultsContainer = document.getElementById('employee-search-results');
  const resultsList = document.getElementById('employee-results-list');
  const loadingIndicator = document.getElementById('employee-search-loading');
  const errorContainer = document.getElementById('employee-search-error');

  if (!searchInput || !searchWidget) {
    console.log('Employee search widget not found - exiting');
    return; // Exit if widget not present
  }

  // Get project_id from data attribute
  const projectId = searchWidget.dataset.projectId;
  console.log('Employee search widget initialized with project_id:', projectId);
  if (!projectId) {
    console.error('No project_id found on employee search widget - data-project-id attribute is missing');
    return;
  }

  // Clean up previous initialization
  cleanupEmployeeSearch();

  // Reset state
  employeeSearchState.searchTimeout = null;
  employeeSearchState.currentRequest = null;
  employeeSearchState.fieldMappings = null;
  employeeSearchState.currentSearchQuery = '';
  employeeSearchState.currentOffset = 0;
  employeeSearchState.hasMore = false;
  employeeSearchState.isLoadingMore = false;
  employeeSearchState.initialized = true;

  // Load field mappings on initialization
  loadFieldMappings();

  const inputHandler = function() {
    const query = this.value.trim();

    // Clear any existing timeout
    if (employeeSearchState.searchTimeout) {
      clearTimeout(employeeSearchState.searchTimeout);
    }

    // Cancel any existing request
    if (employeeSearchState.currentRequest) {
      employeeSearchState.currentRequest.abort();
      employeeSearchState.currentRequest = null;
    }

    // Hide results if query is too short
    if (query.length < 2) {
      hideResults();
      return;
    }

    // Debounce search requests
    employeeSearchState.searchTimeout = setTimeout(() => {
      performSearch(query);
    }, 300);
  };
  searchInput.addEventListener('input', inputHandler);
  employeeSearchState.listeners.push({ element: searchInput, event: 'input', handler: inputHandler });

  const keydownHandler = function(e) {
    if (e.key === 'Escape') {
      hideResults();
      this.blur();
    }
  };
  searchInput.addEventListener('keydown', keydownHandler);
  employeeSearchState.listeners.push({ element: searchInput, event: 'keydown', handler: keydownHandler });

  // Hide results when clicking outside
  const clickHandler = function(e) {
    if (!e.target.closest('.employee-search-widget')) {
      hideResults();
    }
  };
  document.addEventListener('click', clickHandler);
  employeeSearchState.listeners.push({ element: document, event: 'click', handler: clickHandler });

  // Add scroll listener for infinite scroll
  const scrollHandler = function() {
    if (employeeSearchState.isLoadingMore || !employeeSearchState.hasMore) return;

    const scrollTop = this.scrollTop;
    const scrollHeight = this.scrollHeight;
    const clientHeight = this.clientHeight;

    // Load more when scrolled to 80% of the content
    if (scrollTop + clientHeight >= scrollHeight * 0.8) {
      loadMoreResults();
    }
  };
  resultsContainer.addEventListener('scroll', scrollHandler);
  employeeSearchState.listeners.push({ element: resultsContainer, event: 'scroll', handler: scrollHandler });

  function performSearch(query) {
    employeeSearchState.currentSearchQuery = query;
    employeeSearchState.currentOffset = 0;
    employeeSearchState.hasMore = false;
    showLoading();
    hideError();

    employeeSearchState.currentRequest = new XMLHttpRequest();
    employeeSearchState.currentRequest.open('GET', `/employee_search/search?q=${encodeURIComponent(query)}&limit=20&offset=0&project_id=${encodeURIComponent(projectId)}`);
    employeeSearchState.currentRequest.setRequestHeader('Accept', 'application/json');
    employeeSearchState.currentRequest.setRequestHeader('X-Requested-With', 'XMLHttpRequest');

    employeeSearchState.currentRequest.onreadystatechange = function() {
      if (this.readyState === XMLHttpRequest.DONE) {
        hideLoading();

        if (this.status === 200) {
          try {
            const response = JSON.parse(this.responseText);
            employeeSearchState.hasMore = response.has_more || false;
            employeeSearchState.currentOffset = response.offset + response.total;
            displayResults(response.employees || [], false);
          } catch (e) {
            showError('Error parsing search results');
          }
        } else if (this.status === 403) {
          showError('Access denied. You do not have permission to search employees.');
        } else if (this.status === 503) {
          showError('Employee search temporarily unavailable. Please try again later.');
        } else {
          showError('Search failed. Please try again.');
        }

        employeeSearchState.currentRequest = null;
      }
    };

    employeeSearchState.currentRequest.onerror = function() {
      hideLoading();
      showError('Network error. Please check your connection.');
      employeeSearchState.currentRequest = null;
    };

    employeeSearchState.currentRequest.send();
  }

  function loadMoreResults() {
    if (employeeSearchState.isLoadingMore || !employeeSearchState.hasMore || !employeeSearchState.currentSearchQuery) return;

    employeeSearchState.isLoadingMore = true;
    showLoadingMore();

    const request = new XMLHttpRequest();
    request.open('GET', `/employee_search/search?q=${encodeURIComponent(employeeSearchState.currentSearchQuery)}&limit=20&offset=${employeeSearchState.currentOffset}&project_id=${encodeURIComponent(projectId)}`);
    request.setRequestHeader('Accept', 'application/json');
    request.setRequestHeader('X-Requested-With', 'XMLHttpRequest');

    request.onreadystatechange = function() {
      if (this.readyState === XMLHttpRequest.DONE) {
        hideLoadingMore();
        employeeSearchState.isLoadingMore = false;

        if (this.status === 200) {
          try {
            const response = JSON.parse(this.responseText);
            employeeSearchState.hasMore = response.has_more || false;
            employeeSearchState.currentOffset = employeeSearchState.currentOffset + response.total;
            displayResults(response.employees || [], true);
          } catch (e) {
            console.error('Error parsing more results:', e);
          }
        } else {
          console.error('Failed to load more results. Status:', this.status);
        }
      }
    };

    request.onerror = function() {
      hideLoadingMore();
      employeeSearchState.isLoadingMore = false;
      console.error('Network error loading more results');
    };

    request.send();
  }

  function displayResults(employees, append = false) {
    if (!append) {
      resultsList.innerHTML = '';
    }

    // Remove loading indicator if it exists
    const existingLoader = resultsList.querySelector('.loading-more-indicator');
    if (existingLoader) {
      existingLoader.remove();
    }

    if (employees.length === 0 && !append) {
      resultsList.innerHTML = '<li class="no-results">No employees found</li>';
    } else {
      employees.forEach(employee => {
        const li = document.createElement('li');
        const statusClass = employee.status === 'Active' ? 'employee-status-active' : 'employee-status-inactive';
        li.innerHTML = `
          <div class="employee-name">${highlightMatch(employee.name || 'Unknown', employeeSearchState.currentSearchQuery)}</div>
          <div class="employee-details">
            Status: <span class="${statusClass}">${escapeHtml(employee.status || 'N/A')}</span> |
            UID: ${escapeHtml(employee.uid || 'N/A')} |
            Office: ${escapeHtml(employee.office || 'N/A')} |
            ID #: ${escapeHtml(employee.employee_id || 'N/A')}
          </div>
        `;

        li.addEventListener('click', () => {
          selectEmployee(employee);
        });

        resultsList.appendChild(li);
      });
    }

    showResults();
  }

  function loadFieldMappings() {
    console.log('Starting field mappings load...');
    const request = new XMLHttpRequest();
    request.open('GET', `/employee_search/field_mappings?project_id=${encodeURIComponent(projectId)}`);
    request.setRequestHeader('Accept', 'application/json');
    request.setRequestHeader('X-Requested-With', 'XMLHttpRequest');

    request.onreadystatechange = function() {
      console.log('Field mappings request state:', this.readyState, this.status);
      if (this.readyState === XMLHttpRequest.DONE) {
        if (this.status === 200) {
          try {
            console.log('Field mappings response text:', this.responseText);
            const response = JSON.parse(this.responseText);
            employeeSearchState.fieldMappings = response.field_mappings;
            console.log('Field mappings loaded successfully:', employeeSearchState.fieldMappings);
            window.bachelpFieldMappings = employeeSearchState.fieldMappings; // Also set globally for debugging
          } catch (e) {
            console.error('Error parsing field mappings:', e);
          }
        } else {
          console.error('Failed to load field mappings. Status:', this.status, 'Response:', this.responseText);
        }
      }
    };

    request.send();
    console.log('Field mappings request sent');
  }

  function selectEmployee(employee) {
    console.log('Selected employee:', employee);
    console.log('Current fieldMappings state:', employeeSearchState.fieldMappings);
    hideResults();
    searchInput.value = employee.name || '';

    if (!employeeSearchState.fieldMappings) {
      console.warn('Field mappings not loaded yet, trying to use global fallback...');
      if (window.bachelpFieldMappings) {
        employeeSearchState.fieldMappings = window.bachelpFieldMappings;
        console.log('Using global field mappings:', employeeSearchState.fieldMappings);
      } else {
        console.error('No field mappings available, cannot autofill');
        return;
      }
    }

    populateEmployeeFields(employee);
  }
  
  function populateEmployeeFields(employee) {
    // Populate employee fields using dynamic mappings
    populateField('employee_id_field', employee.employee_id);
    populateField('employee_name_field', employee.name);
    populateField('employee_email_field', employee.email);
    populateField('employee_phone_field', employee.phone);
    populateField('employee_uid_field', employee.uid);
    populateField('employee_office_field', employee.office);

    // Populate Employee Status dropdown if mapping exists
    if (employee.status) {
      populateSelectField('employee_status_field', employee.status);
    }
  }

  function populateField(mappingKey, value) {
    if (!employeeSearchState.fieldMappings || !employeeSearchState.fieldMappings[mappingKey]) return;

    const fieldId = employeeSearchState.fieldMappings[mappingKey];
    const input = document.getElementById(fieldId);

    if (input) {
      input.value = value || '';
      // Trigger change event for any listeners
      input.dispatchEvent(new Event('change', { bubbles: true }));
      input.dispatchEvent(new Event('input', { bubbles: true }));
      console.log(`Populated ${mappingKey} (${fieldId}) with value: ${value || '(blank)'}`);
    } else {
      console.warn(`Could not find input field for ${mappingKey} (${fieldId})`);
    }
  }

  function populateSelectField(mappingKey, value) {
    if (!employeeSearchState.fieldMappings || !employeeSearchState.fieldMappings[mappingKey]) return;

    const fieldId = employeeSearchState.fieldMappings[mappingKey];
    const select = document.getElementById(fieldId);

    if (select && select.tagName === 'SELECT') {
      if (!value) {
        // Clear selection by selecting empty/default option
        select.value = '';
        select.dispatchEvent(new Event('change', { bubbles: true }));
        console.log(`Cleared ${mappingKey} (${fieldId})`);
        return;
      }

      // Try to find matching option by value or text
      const options = select.querySelectorAll('option');
      for (const option of options) {
        if (option.value === value || option.textContent.trim() === value) {
          select.value = option.value;
          select.dispatchEvent(new Event('change', { bubbles: true }));
          console.log(`Populated ${mappingKey} (${fieldId}) with value: ${value}`);
          return;
        }
      }
      console.warn(`Could not find option "${value}" in select field ${mappingKey} (${fieldId})`);
    } else {
      console.warn(`Could not find select field for ${mappingKey} (${fieldId})`);
    }
  }

  function showResults() {
    resultsContainer.style.display = 'block';
  }

  function hideResults() {
    resultsContainer.style.display = 'none';
  }

  function showLoading() {
    loadingIndicator.style.display = 'block';
  }

  function hideLoading() {
    loadingIndicator.style.display = 'none';
  }

  function showError(message) {
    errorContainer.textContent = message;
    errorContainer.style.display = 'block';
  }

  function hideError() {
    errorContainer.style.display = 'none';
  }

  function showLoadingMore() {
    // Remove any existing loading indicator
    const existingLoader = resultsList.querySelector('.loading-more-indicator');
    if (existingLoader) {
      existingLoader.remove();
    }

    const li = document.createElement('li');
    li.className = 'loading-more-indicator';
    li.textContent = 'Loading more results...';
    resultsList.appendChild(li);
  }

  function hideLoadingMore() {
    const loader = resultsList.querySelector('.loading-more-indicator');
    if (loader) {
      loader.remove();
    }
  }

  function escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
  }

  function highlightMatch(text, query) {
    if (!query || !text) {
      return escapeHtml(text);
    }

    const escapedText = escapeHtml(text);
    const regex = new RegExp(`(${escapeRegex(query)})`, 'gi');
    return escapedText.replace(regex, '<mark class="search-highlight">$1</mark>');
  }

  function escapeRegex(str) {
    return str.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  }
}

function cleanupEmployeeSearch() {
  console.log('Cleaning up employee search...');

  // Clear any pending timeout
  if (employeeSearchState.searchTimeout) {
    clearTimeout(employeeSearchState.searchTimeout);
    employeeSearchState.searchTimeout = null;
  }

  // Abort any pending request
  if (employeeSearchState.currentRequest) {
    employeeSearchState.currentRequest.abort();
    employeeSearchState.currentRequest = null;
  }

  // Remove all event listeners
  employeeSearchState.listeners.forEach(({ element, event, handler }) => {
    element.removeEventListener(event, handler);
  });
  employeeSearchState.listeners = [];

  console.log('Cleanup complete');
}

// Initialize on DOMContentLoaded
document.addEventListener('DOMContentLoaded', function() {
  console.log('DOMContentLoaded: Initializing employee search');
  initializeEmployeeSearch();
});

// Re-initialize when issue form is updated via AJAX (e.g., project change)
// Listen for both jQuery ajaxComplete and native events
if (typeof jQuery !== 'undefined') {
  jQuery(document).on('ajaxComplete', function(event, xhr, settings) {
    // Check if this is an issue form update
    if (settings.url && settings.url.includes('/issues/') && settings.url.includes('/edit')) {
      console.log('AJAX form update detected, re-initializing employee search');
      // Small delay to ensure DOM is updated
      setTimeout(function() {
        if (document.getElementById('employee-search-widget')) {
          initializeEmployeeSearch();
        }
      }, 100);
    }
  });
}