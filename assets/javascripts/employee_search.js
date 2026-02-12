document.addEventListener('DOMContentLoaded', function() {
  const searchWidget = document.getElementById('employee-search-widget');
  const searchInput = document.getElementById('employee-search-input');
  const resultsContainer = document.getElementById('employee-search-results');
  const resultsList = document.getElementById('employee-results-list');
  const loadingIndicator = document.getElementById('employee-search-loading');
  const errorContainer = document.getElementById('employee-search-error');

  let searchTimeout = null;
  let currentRequest = null;
  let fieldMappings = null;
  let currentSearchQuery = '';
  let currentOffset = 0;
  let hasMore = false;
  let isLoadingMore = false;

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

  // Load field mappings on initialization
  loadFieldMappings();

  searchInput.addEventListener('input', function() {
    const query = this.value.trim();
    
    // Clear any existing timeout
    if (searchTimeout) {
      clearTimeout(searchTimeout);
    }
    
    // Cancel any existing request
    if (currentRequest) {
      currentRequest.abort();
      currentRequest = null;
    }
    
    // Hide results if query is too short
    if (query.length < 2) {
      hideResults();
      return;
    }
    
    // Debounce search requests
    searchTimeout = setTimeout(() => {
      performSearch(query);
    }, 300);
  });

  searchInput.addEventListener('keydown', function(e) {
    if (e.key === 'Escape') {
      hideResults();
      this.blur();
    }
  });

  // Hide results when clicking outside
  document.addEventListener('click', function(e) {
    if (!e.target.closest('.employee-search-widget')) {
      hideResults();
    }
  });

  // Add scroll listener for infinite scroll
  resultsContainer.addEventListener('scroll', function() {
    if (isLoadingMore || !hasMore) return;

    const scrollTop = this.scrollTop;
    const scrollHeight = this.scrollHeight;
    const clientHeight = this.clientHeight;

    // Load more when scrolled to 80% of the content
    if (scrollTop + clientHeight >= scrollHeight * 0.8) {
      loadMoreResults();
    }
  });

  function performSearch(query) {
    currentSearchQuery = query;
    currentOffset = 0;
    hasMore = false;
    showLoading();
    hideError();

    currentRequest = new XMLHttpRequest();
    currentRequest.open('GET', `/employee_search/search?q=${encodeURIComponent(query)}&limit=20&offset=0&project_id=${encodeURIComponent(projectId)}`);
    currentRequest.setRequestHeader('Accept', 'application/json');
    currentRequest.setRequestHeader('X-Requested-With', 'XMLHttpRequest');

    currentRequest.onreadystatechange = function() {
      if (this.readyState === XMLHttpRequest.DONE) {
        hideLoading();

        if (this.status === 200) {
          try {
            const response = JSON.parse(this.responseText);
            hasMore = response.has_more || false;
            currentOffset = response.offset + response.total;
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

        currentRequest = null;
      }
    };

    currentRequest.onerror = function() {
      hideLoading();
      showError('Network error. Please check your connection.');
      currentRequest = null;
    };

    currentRequest.send();
  }

  function loadMoreResults() {
    if (isLoadingMore || !hasMore || !currentSearchQuery) return;

    isLoadingMore = true;
    showLoadingMore();

    const request = new XMLHttpRequest();
    request.open('GET', `/employee_search/search?q=${encodeURIComponent(currentSearchQuery)}&limit=20&offset=${currentOffset}&project_id=${encodeURIComponent(projectId)}`);
    request.setRequestHeader('Accept', 'application/json');
    request.setRequestHeader('X-Requested-With', 'XMLHttpRequest');

    request.onreadystatechange = function() {
      if (this.readyState === XMLHttpRequest.DONE) {
        hideLoadingMore();
        isLoadingMore = false;

        if (this.status === 200) {
          try {
            const response = JSON.parse(this.responseText);
            hasMore = response.has_more || false;
            currentOffset = currentOffset + response.total;
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
      isLoadingMore = false;
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
          <div class="employee-name">${highlightMatch(employee.name || 'Unknown', currentSearchQuery)}</div>
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
            fieldMappings = response.field_mappings;
            console.log('Field mappings loaded successfully:', fieldMappings);
            window.bachelpFieldMappings = fieldMappings; // Also set globally for debugging
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

  function loadFieldMappingsSync() {
    return fetch(`/employee_search/field_mappings?project_id=${encodeURIComponent(projectId)}`, {
      headers: {
        'Accept': 'application/json',
        'X-Requested-With': 'XMLHttpRequest'
      }
    })
    .then(response => response.json())
    .then(data => {
      fieldMappings = data.field_mappings;
      console.log('Field mappings loaded synchronously:', fieldMappings);
      return fieldMappings;
    })
    .catch(error => {
      console.error('Failed to load field mappings synchronously:', error);
      return null;
    });
  }

  function selectEmployee(employee) {
    console.log('Selected employee:', employee);
    console.log('Current fieldMappings state:', fieldMappings);
    hideResults();
    searchInput.value = employee.name || '';
    
    if (!fieldMappings) {
      console.warn('Field mappings not loaded yet, trying to use global fallback...');
      if (window.bachelpFieldMappings) {
        fieldMappings = window.bachelpFieldMappings;
        console.log('Using global field mappings:', fieldMappings);
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
    if (!fieldMappings || !fieldMappings[mappingKey]) return;

    const fieldId = fieldMappings[mappingKey];
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
    if (!fieldMappings || !fieldMappings[mappingKey]) return;

    const fieldId = fieldMappings[mappingKey];
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
});