// Global state for cleanup
let subjectSearchState = {
  initialized: false,
  listeners: [],
  searchTimeout: null,
  currentRequest: null,
  fieldMappings: null,
  currentSearchQuery: '',
  currentOffset: 0,
  hasMore: false,
  isLoadingMore: false,
  selectedType: 'Employee' // Default to Employee
};

function initializeSubjectSearch() {
  const searchWidget = document.getElementById('subject-search-widget');
  const searchInput = document.getElementById('subject-search-input');
  const resultsContainer = document.getElementById('subject-search-results');
  const resultsList = document.getElementById('subject-results-list');
  const loadingIndicator = document.getElementById('subject-search-loading');
  const errorContainer = document.getElementById('subject-search-error');
  const typeRadios = document.querySelectorAll('input[name="subject-type"]');

  if (!searchInput || !searchWidget) {
    console.log('Subject search widget not found - exiting');
    return; // Exit if widget not present
  }

  // Get project_id from data attribute
  const projectId = searchWidget.dataset.projectId;
  console.log('Subject search widget initialized with project_id:', projectId);
  if (!projectId) {
    console.error('No project_id found on subject search widget - data-project-id attribute is missing');
    return;
  }

  // Clean up previous initialization
  cleanupSubjectSearch();

  // Reset state
  subjectSearchState.searchTimeout = null;
  subjectSearchState.currentRequest = null;
  subjectSearchState.fieldMappings = null;
  subjectSearchState.currentSearchQuery = '';
  subjectSearchState.currentOffset = 0;
  subjectSearchState.hasMore = false;
  subjectSearchState.isLoadingMore = false;
  subjectSearchState.selectedType = 'Employee'; // Default to Employee
  subjectSearchState.initialized = true;

  // Load field mappings on initialization
  loadFieldMappings();

  // Update placeholder based on selected type
  updatePlaceholder();

  // Type selector change handler
  typeRadios.forEach(radio => {
    const typeChangeHandler = function() {
      subjectSearchState.selectedType = this.value;
      console.log('Subject type changed to:', subjectSearchState.selectedType);
      updatePlaceholder();
      hideResults();
      hideError();
      // Clear search input and results when type changes
      searchInput.value = '';
    };
    radio.addEventListener('change', typeChangeHandler);
    subjectSearchState.listeners.push({ element: radio, event: 'change', handler: typeChangeHandler });
  });

  const inputHandler = function() {
    const query = this.value.trim();

    // Clear any existing timeout
    if (subjectSearchState.searchTimeout) {
      clearTimeout(subjectSearchState.searchTimeout);
    }

    // Cancel any existing request
    if (subjectSearchState.currentRequest) {
      subjectSearchState.currentRequest.abort();
      subjectSearchState.currentRequest = null;
    }

    // Hide results if query is too short
    if (query.length < 2) {
      hideResults();
      return;
    }

    // Debounce search requests
    subjectSearchState.searchTimeout = setTimeout(() => {
      performSearch(query);
    }, 300);
  };
  searchInput.addEventListener('input', inputHandler);
  subjectSearchState.listeners.push({ element: searchInput, event: 'input', handler: inputHandler });

  const keydownHandler = function(e) {
    if (e.key === 'Escape') {
      hideResults();
      this.blur();
    }
  };
  searchInput.addEventListener('keydown', keydownHandler);
  subjectSearchState.listeners.push({ element: searchInput, event: 'keydown', handler: keydownHandler });

  // Hide results when clicking outside
  const clickHandler = function(e) {
    if (!e.target.closest('.subject-search-widget')) {
      hideResults();
    }
  };
  document.addEventListener('click', clickHandler);
  subjectSearchState.listeners.push({ element: document, event: 'click', handler: clickHandler });

  // Add scroll listener for infinite scroll
  const scrollHandler = function() {
    if (subjectSearchState.isLoadingMore || !subjectSearchState.hasMore) return;

    const scrollTop = this.scrollTop;
    const scrollHeight = this.scrollHeight;
    const clientHeight = this.clientHeight;

    // Load more when scrolled to 80% of the content
    if (scrollTop + clientHeight >= scrollHeight * 0.8) {
      loadMoreResults();
    }
  };
  resultsContainer.addEventListener('scroll', scrollHandler);
  subjectSearchState.listeners.push({ element: resultsContainer, event: 'scroll', handler: scrollHandler });

  function updatePlaceholder() {
    const searchInput = document.getElementById('subject-search-input');
    if (searchInput) {
      if (subjectSearchState.selectedType === 'Employee') {
        searchInput.placeholder = 'Search for employee by name';
      } else if (subjectSearchState.selectedType === 'Vendor') {
        searchInput.placeholder = 'Search for vendor by name';
      } else {
        searchInput.placeholder = 'Search for subject by name';
      }
    }
  }

  function performSearch(query) {
    subjectSearchState.currentSearchQuery = query;
    subjectSearchState.currentOffset = 0;
    subjectSearchState.hasMore = false;
    showLoading();
    hideError();

    subjectSearchState.currentRequest = new XMLHttpRequest();
    subjectSearchState.currentRequest.open('GET', `/subject_search/search?q=${encodeURIComponent(query)}&type=${encodeURIComponent(subjectSearchState.selectedType)}&limit=20&offset=0&project_id=${encodeURIComponent(projectId)}`);
    subjectSearchState.currentRequest.setRequestHeader('Accept', 'application/json');
    subjectSearchState.currentRequest.setRequestHeader('X-Requested-With', 'XMLHttpRequest');

    subjectSearchState.currentRequest.onreadystatechange = function() {
      if (this.readyState === XMLHttpRequest.DONE) {
        hideLoading();

        if (this.status === 200) {
          try {
            const response = JSON.parse(this.responseText);
            subjectSearchState.hasMore = response.has_more || false;
            subjectSearchState.currentOffset = response.offset + response.total;
            displayResults(response.subjects || [], false);
          } catch (e) {
            showError('Error parsing search results');
          }
        } else if (this.status === 403) {
          showError('Access denied. You do not have permission to search subjects.');
        } else if (this.status === 503) {
          showError('Subject search temporarily unavailable. Please try again later.');
        } else {
          showError('Search failed. Please try again.');
        }

        subjectSearchState.currentRequest = null;
      }
    };

    subjectSearchState.currentRequest.onerror = function() {
      hideLoading();
      showError('Network error. Please check your connection.');
      subjectSearchState.currentRequest = null;
    };

    subjectSearchState.currentRequest.send();
  }

  function loadMoreResults() {
    if (subjectSearchState.isLoadingMore || !subjectSearchState.hasMore || !subjectSearchState.currentSearchQuery) return;

    subjectSearchState.isLoadingMore = true;
    showLoadingMore();

    const request = new XMLHttpRequest();
    request.open('GET', `/subject_search/search?q=${encodeURIComponent(subjectSearchState.currentSearchQuery)}&type=${encodeURIComponent(subjectSearchState.selectedType)}&limit=20&offset=${subjectSearchState.currentOffset}&project_id=${encodeURIComponent(projectId)}`);
    request.setRequestHeader('Accept', 'application/json');
    request.setRequestHeader('X-Requested-With', 'XMLHttpRequest');

    request.onreadystatechange = function() {
      if (this.readyState === XMLHttpRequest.DONE) {
        hideLoadingMore();
        subjectSearchState.isLoadingMore = false;

        if (this.status === 200) {
          try {
            const response = JSON.parse(this.responseText);
            subjectSearchState.hasMore = response.has_more || false;
            subjectSearchState.currentOffset = subjectSearchState.currentOffset + response.total;
            displayResults(response.subjects || [], true);
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
      subjectSearchState.isLoadingMore = false;
      console.error('Network error loading more results');
    };

    request.send();
  }

  function displayResults(subjects, append = false) {
    if (!append) {
      resultsList.innerHTML = '';
    }

    // Remove loading indicator if it exists
    const existingLoader = resultsList.querySelector('.loading-more-indicator');
    if (existingLoader) {
      existingLoader.remove();
    }

    if (subjects.length === 0 && !append) {
      const typeName = subjectSearchState.selectedType.toLowerCase();
      resultsList.innerHTML = `<li class="no-results">No ${typeName}s found</li>`;
    } else {
      subjects.forEach(subject => {
        const li = document.createElement('li');
        const statusClass = subject.status === 'Active' ? 'subject-status-active' : 'subject-status-inactive';

        // Build details based on available information
        let details = `Status: <span class="${statusClass}">${escapeHtml(subject.status || 'N/A')}</span>`;
        if (subject.uid) {
          details += ` | UID: ${escapeHtml(subject.uid)}`;
        }
        if (subject.location) {
          details += ` | Location: ${escapeHtml(subject.location)}`;
        }
        if (subject.subject_id) {
          details += ` | ID #: ${escapeHtml(subject.subject_id)}`;
        }

        li.innerHTML = `
          <div class="subject-name">${highlightMatch(subject.name || 'Unknown', subjectSearchState.currentSearchQuery)}</div>
          <div class="subject-details">${details}</div>
        `;

        li.addEventListener('click', () => {
          selectSubject(subject);
        });

        resultsList.appendChild(li);
      });
    }

    showResults();
  }

  function loadFieldMappings() {
    console.log('Starting field mappings load...');
    const request = new XMLHttpRequest();
    request.open('GET', `/subject_search/field_mappings?project_id=${encodeURIComponent(projectId)}`);
    request.setRequestHeader('Accept', 'application/json');
    request.setRequestHeader('X-Requested-With', 'XMLHttpRequest');

    request.onreadystatechange = function() {
      console.log('Field mappings request state:', this.readyState, this.status);
      if (this.readyState === XMLHttpRequest.DONE) {
        if (this.status === 200) {
          try {
            console.log('Field mappings response text:', this.responseText);
            const response = JSON.parse(this.responseText);
            subjectSearchState.fieldMappings = response.field_mappings;
            console.log('Field mappings loaded successfully:', subjectSearchState.fieldMappings);
            window.bachelpFieldMappings = subjectSearchState.fieldMappings; // Also set globally for debugging
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

  function selectSubject(subject) {
    console.log('Selected subject:', subject);
    console.log('Current fieldMappings state:', subjectSearchState.fieldMappings);
    hideResults();
    searchInput.value = subject.name || '';

    if (!subjectSearchState.fieldMappings) {
      console.warn('Field mappings not loaded yet, trying to use global fallback...');
      if (window.bachelpFieldMappings) {
        subjectSearchState.fieldMappings = window.bachelpFieldMappings;
        console.log('Using global field mappings:', subjectSearchState.fieldMappings);
      } else {
        console.error('No field mappings available, cannot autofill');
        return;
      }
    }

    populateSubjectFields(subject);
  }

  function populateSubjectFields(subject) {
    // Populate subject fields using dynamic mappings
    populateField('subject_id_field', subject.subject_id);
    populateField('subject_name_field', subject.name);
    populateField('subject_email_field', subject.email);
    populateField('subject_phone_field', subject.phone);
    populateField('subject_uid_field', subject.uid);
    populateField('subject_location_field', subject.location);

    // Populate Subject Status dropdown if mapping exists
    if (subject.status) {
      populateSelectField('subject_status_field', subject.status);
    }

    // Populate Subject Type dropdown if mapping exists
    if (subject.subject_type) {
      populateSelectField('subject_type_field', subject.subject_type);
    } else {
      // If subject_type not provided, use the selected type from the search
      populateSelectField('subject_type_field', subjectSearchState.selectedType);
    }
  }

  function populateField(mappingKey, value) {
    if (!subjectSearchState.fieldMappings || !subjectSearchState.fieldMappings[mappingKey]) return;

    const fieldId = subjectSearchState.fieldMappings[mappingKey];
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
    if (!subjectSearchState.fieldMappings || !subjectSearchState.fieldMappings[mappingKey]) return;

    const fieldId = subjectSearchState.fieldMappings[mappingKey];
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

function cleanupSubjectSearch() {
  console.log('Cleaning up subject search...');

  // Clear any pending timeout
  if (subjectSearchState.searchTimeout) {
    clearTimeout(subjectSearchState.searchTimeout);
    subjectSearchState.searchTimeout = null;
  }

  // Abort any pending request
  if (subjectSearchState.currentRequest) {
    subjectSearchState.currentRequest.abort();
    subjectSearchState.currentRequest = null;
  }

  // Remove all event listeners
  subjectSearchState.listeners.forEach(({ element, event, handler }) => {
    element.removeEventListener(event, handler);
  });
  subjectSearchState.listeners = [];

  console.log('Cleanup complete');
}

// Initialize on DOMContentLoaded
document.addEventListener('DOMContentLoaded', function() {
  console.log('DOMContentLoaded: Initializing subject search');
  initializeSubjectSearch();
});

// Re-initialize when issue form is updated via AJAX (e.g., project change)
// Listen for both jQuery ajaxComplete and native events
if (typeof jQuery !== 'undefined') {
  jQuery(document).on('ajaxComplete', function(event, xhr, settings) {
    // Check if this is an issue form update
    if (settings.url && settings.url.includes('/issues/') && settings.url.includes('/edit')) {
      console.log('AJAX form update detected, re-initializing subject search');
      // Small delay to ensure DOM is updated
      setTimeout(function() {
        if (document.getElementById('subject-search-widget')) {
          initializeSubjectSearch();
        }
      }, 100);
    }
  });
}
