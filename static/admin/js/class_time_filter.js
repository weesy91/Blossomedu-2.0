/* static/admin/js/class_time_filter.js */

(function($) {
    const FIELD_RULES = [
        { suffix: 'syntax_class', keyword: '구문', typeDependency: false },
        { suffix: 'reading_class', keyword: '독해', typeDependency: false },
        { suffix: 'extra_class', keyword: '',     typeDependency: true }
    ];

    $(document).ready(function() {
        console.log("🚀 Class Time Filter Loaded (Edit Mode Support)");

        // 1. 페이지 로드 시 모든 행 초기화
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
        const branchId = $branchSelect.attr('id');
        if (!branchId) return;

        const prefix = branchId.substring(0, branchId.lastIndexOf('-'));
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

                // (3) 추가수업 타입 연동
                if (rule.typeDependency) {
                    const $typeSelect = $('#' + prefix + '-extra_class_type');
                    if ($typeSelect.length > 0) {
                        targetObj.$typeEl = $typeSelect;
                        $typeSelect.on('change', function() {
                            renderOptions(targetObj);
                        });
                    }
                }
                targets.push(targetObj);
            }
        });

        // 3. 지점 변경 이벤트
        $branchSelect.off('change.classTimeFilter').on('change.classTimeFilter', function() {
            updateClassTimes($(this).val(), targets);
        });

        // ✅ [핵심 해결책] 페이지 로딩 시, 이미 지점이 선택되어 있다면(수정 모드)
        // 즉시 서버에서 시간표를 가져와서 '모든 시간표'를 '해당 지점 시간표'로 덮어씌웁니다.
        if ($branchSelect.val()) {
            // console.log("🔄 수정 모드 감지: 시간표 데이터 초기화 중...");
            updateClassTimes($branchSelect.val(), targets);
        }
    }

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

        $dayFilter.on('change', function() {
            // 요일 변경 시에는 renderOptions 호출 대신 trigger로 처리하거나
            // 간편하게 해당 select에 이벤트를 전달
            const $relatedSelect = $select;
            // 여기서 직접 DOM 필터링 수행
            applyDayFilter($relatedSelect, $(this).val());
        });
    }

    // 요일 필터 적용 함수
    function applyDayFilter($select, dayVal) {
        const $master = $select.data('master-options');
        if (!$master) return;

        let $options = $master.clone();
        
        // 추가수업 타입 필터 (DOM에서 찾아서 적용)
        const nameAttr = $select.attr('name');
        if (nameAttr && nameAttr.indexOf('extra_class') !== -1) {
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

        // 요일 필터
        if (dayVal) {
            $options = $options.filter((i, el) => el.value === "" || $(el).text().indexOf(dayVal) !== -1);
        }

        const currentVal = $select.val();
        $select.empty().append($options);
        if (currentVal) $select.val(currentVal);

        // 🔄 필터링 후 중복 검사 재요청
        $select.trigger('options_refreshed');
    }


    function updateClassTimes(branchId, targets) {
        if (!branchId) {
            targets.forEach(t => {
                t.$el.html('<option value="">---------</option>');
                t.$el.data('master-options', null);
                t.$el.trigger('options_refreshed');
            });
            return;
        }

        $.ajax({
            url: '/core/api/get-classtimes/',
            data: { 'branch_id': branchId },
            success: function(data) {
                targets.forEach(function(target) {
                    let filteredHtml = '<option value="">---------</option>';
                    $.each(data, function(idx, item) {
                        if (target.keyword === "" || item.name.indexOf(target.keyword) !== -1) {
                            filteredHtml += '<option value="' + item.id + '">' + item.name + '</option>';
                        }
                    });

                    const $newOptions = $(filteredHtml);
                    target.$el.data('master-options', $newOptions); 
                    
                    // 화면 그리기
                    renderOptions(target);
                });
            },
            error: function() {
                // 에러 시 조용히 처리
            }
        });
    }

    function renderOptions(target) {
        const $select = target.$el;
        const $master = $select.data('master-options');
        if (!$master) return;

        let $options = $master.clone();

        // 1. 추가수업 타입 필터
        if (target.rule.typeDependency && target.$typeEl) {
            const typeVal = target.$typeEl.val();
            if (typeVal === 'SYNTAX') {
                $options = $options.filter((i, el) => el.value === "" || $(el).text().indexOf('구문') !== -1);
            } else if (typeVal === 'READING') {
                $options = $options.filter((i, el) => el.value === "" || $(el).text().indexOf('독해') !== -1);
            }
        }

        // 2. 요일 필터
        const $dayFilter = $select.prev('.day-filter-box');
        if ($dayFilter.length > 0) {
            const dayVal = $dayFilter.val();
            if (dayVal) {
                $options = $options.filter((i, el) => el.value === "" || $(el).text().indexOf(dayVal) !== -1);
            }
        }

        const currentVal = $select.val();
        $select.empty().append($options);
        
        // 기존 값이 새 목록에 있다면 유지
        if (currentVal) $select.val(currentVal);

        // ✅ [핵심] 목록 갱신 완료! 중복 검사 다시 실행하라고 신호 보냄
        $select.trigger('options_refreshed');
    }

})(django.jQuery);