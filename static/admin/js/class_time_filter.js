/* static/admin/js/class_time_filter.js */

(function($) {
    /**
     * [설정] 과목별 필터링 규칙
     * - keyword: 수업명에 이 단어가 포함되어야 함 (빈값이면 전체)
     * - typeDependency: 추가수업처럼 별도의 '타입 선택 박스'에 영향을 받는지 여부
     */
    const FIELD_RULES = [
        { suffix: 'syntax_class', keyword: '구문', typeDependency: false },
        { suffix: 'reading_class', keyword: '독해', typeDependency: false },
        { suffix: 'extra_class', keyword: '',     typeDependency: true } // 추가수업은 타입(구문/독해)에 따라 또 걸러짐
    ];

    $(document).ready(function() {
        console.log("🚀 통합 시간표 필터(지점+타입+요일) 시작");

        // 1. 로드 시 모든 행 초기화
        $('select[name$="-branch"]').each(function() {
            initializeRow($(this));
        });

        // 2. 행 추가 시 초기화
        $(document).on('formset:added', function(event, $row, formsetName) {
            $row.find('select[name$="-branch"]').each(function() {
                initializeRow($(this));
            });
        });
    });

    function initializeRow($branchSelect) {
        const branchId = $branchSelect.attr('id'); // 예: id_profile-0-branch
        if (!branchId) return;

        const prefix = branchId.substring(0, branchId.lastIndexOf('-')); // 예: id_profile-0
        
        // 제어할 3개의 시간표 박스 찾기
        const targets = [];

        FIELD_RULES.forEach(function(rule) {
            const $select = $('#' + prefix + '-' + rule.suffix);
            if ($select.length > 0) {
                // (1) 요일 필터 생성
                createDayFilter($select);

                // (2) 타겟 정보 저장
                const targetObj = {
                    $el: $select,
                    keyword: rule.keyword,
                    rule: rule
                };
                
                // (3) '추가수업'인 경우, '추가수업 타입' 박스도 찾아서 이벤트 연결
                if (rule.typeDependency) {
                    // id_profile-0-extra_class_type
                    const $typeSelect = $('#' + prefix + '-extra_class_type');
                    if ($typeSelect.length > 0) {
                        targetObj.$typeEl = $typeSelect;
                        
                        // 타입 변경 시 -> 목록 다시 그리기 (현재 마스터 데이터 기준)
                        $typeSelect.on('change', function() {
                            renderOptions(targetObj); 
                        });
                    }
                }

                targets.push(targetObj);

                // (4) 수정 페이지 진입 시: 현재 있는 옵션을 '원본(Master)'으로 저장
                if ($select.find('option').length > 1) {
                    $select.data('master-options', $select.find('option').clone());
                }
            }
        });

        // 3. 지점 변경 시 -> 서버에서 새 목록 받아오기
        $branchSelect.off('change.classTimeFilter').on('change.classTimeFilter', function() {
            updateClassTimes($(this).val(), targets);
        });
    }

    // [UI] 요일 필터 만들기
    function createDayFilter($select) {
        if ($select.prev('.day-filter-box').length > 0) return;

        const $dayFilter = $('<select class="day-filter-box" style="margin-right:5px; width:90px;">')
            .append('<option value="">📅 요일</option>')
            .append('<option value="월요일">월요일</option>')
            .append('<option value="화요일">화요일</option>')
            .append('<option value="수요일">수요일</option>')
            .append('<option value="목요일">목요일</option>')
            .append('<option value="금요일">금요일</option>')
            .append('<option value="토요일">토요일</option>')
            .append('<option value="일요일">일요일</option>');

        $select.before($dayFilter);

        // 요일 변경 시 -> 목록 다시 그리기
        $dayFilter.on('change', function() {
            // 해당 select 박스와 연결된 targetObj 정보를 찾기는 복잡하므로
            // renderOptions 로직을 간단히 재구현하거나, trigger를 이용
            const $relatedSelect = $select; // closure
            
            // 여기서 바로 필터링 수행
            applyFilters($relatedSelect);
        });
    }

    // [AJAX] 데이터 가져오기
    function updateClassTimes(branchId, targets) {
        if (!branchId) {
            targets.forEach(t => {
                t.$el.html('<option value="">---------</option>');
                t.$el.data('master-options', null);
                t.$el.prev('.day-filter-box').val('');
            });
            return;
        }

        $.ajax({
            url: '/core/api/get-classtimes/',
            data: { 'branch_id': branchId },
            success: function(data) {
                // data: [{id, name}, ...]
                
                targets.forEach(function(target) {
                    // 1. 키워드(구문/독해)로 1차 분류하여 'Master Data' 생성
                    let filteredHtml = '<option value="">---------</option>';
                    $.each(data, function(idx, item) {
                        if (target.keyword === "" || item.name.indexOf(target.keyword) !== -1) {
                            filteredHtml += '<option value="' + item.id + '">' + item.name + '</option>';
                        }
                    });

                    // 2. Master Data 저장
                    const $newOptions = $(filteredHtml);
                    target.$el.data('master-options', $newOptions); 

                    // 3. 화면 렌더링 (추가수업 타입 + 요일 필터 적용)
                    renderOptions(target);
                    
                    // 4. 요일 필터 초기화
                    target.$el.prev('.day-filter-box').val('');
                });
            }
        });
    }

    // [핵심] 저장된 Master Data를 꺼내서 -> 타입 필터 -> 요일 필터 -> 화면 표시
    function renderOptions(target) {
        const $select = target.$el;
        const $master = $select.data('master-options');
        if (!$master) return;

        // 1. Master 복제
        let $options = $master.clone();

        // 2. [필터 A] 추가수업 타입 (구문/독해) 필터링
        if (target.rule.typeDependency && target.$typeEl) {
            const typeVal = target.$typeEl.val(); // SYNTAX, READING ...
            
            if (typeVal === 'SYNTAX') {
                $options = $options.filter((i, el) => {
                    return el.value === "" || $(el).text().indexOf('구문') !== -1;
                });
            } else if (typeVal === 'READING') {
                $options = $options.filter((i, el) => {
                    return el.value === "" || $(el).text().indexOf('독해') !== -1;
                });
            }
        }

        // 3. [필터 B] 요일 필터링
        const $dayFilter = $select.prev('.day-filter-box');
        if ($dayFilter.length > 0) {
            const dayVal = $dayFilter.val();
            if (dayVal) {
                $options = $options.filter((i, el) => {
                    return el.value === "" || $(el).text().indexOf(dayVal) !== -1;
                });
            }
        }

        // 4. DOM 적용
        const currentVal = $select.val();
        $select.empty().append($options);
        if (currentVal) $select.val(currentVal);
    }

    // 요일 필터 이벤트에서 호출할 간소화된 함수
    function applyFilters($select) {
        // 이미 저장된 master-options가 있다고 가정하고,
        // 현재 요일값 등을 읽어서 필터링 (위 renderOptions 로직의 일부와 유사)
        // 역으로 추적하기 어려우므로, renderOptions와 유사하게 동작하되 
        // 추가수업 타입은 DOM에서 직접 찾아야 함.
        
        const $master = $select.data('master-options');
        if (!$master) return;

        let $options = $master.clone();
        
        // 1. 추가수업 타입 체크 (이 select가 extra_class인지 확인)
        const nameAttr = $select.attr('name'); // ...-extra_class
        if (nameAttr && nameAttr.indexOf('extra_class') !== -1) {
            // 이름 기반으로 type select 찾기 (형제 요소)
            // id 예: id_profile-0-extra_class -> id_profile-0-extra_class_type
            const typeId = $select.attr('id').replace('extra_class', 'extra_class_type');
            const $typeEl = $('#' + typeId);
            
            if ($typeEl.length > 0) {
                const typeVal = $typeEl.val();
                if (typeVal === 'SYNTAX') {
                    $options = $options.filter((i, el) => el.value === "" || $(el).text().indexOf('구문') !== -1);
                } else if (typeVal === 'READING') {
                    $options = $options.filter((i, el) => el.value === "" || $(el).text().indexOf('독해') !== -1);
                }
            }
        }

        // 2. 요일 체크
        const dayVal = $select.prev('.day-filter-box').val();
        if (dayVal) {
            $options = $options.filter((i, el) => el.value === "" || $(el).text().indexOf(dayVal) !== -1);
        }

        const currentVal = $select.val();
        $select.empty().append($options);
        if (currentVal) $select.val(currentVal);
    }

})(django.jQuery);