/* static/admin/js/extra_class_filter.js */

(function($) {
    $(document).ready(function() {
        // 1. 필드 선택
        // name 속성으로 찾습니다 (StudentProfileInline 등에서 ID가 변해도 대응 가능)
        var $typeSelect = $('select[name$="-extra_class_type"]');
        var $classSelect = $('select[name$="-extra_class"]');

        if ($typeSelect.length === 0 || $classSelect.length === 0) return;

        // 2. [중요] 원본 옵션들을 메모리에 "복제"해둡니다.
        // (화면에서 지웠다가 다시 살려내기 위함)
        var $allOptions = $classSelect.find('option').clone();

        function updateExtraClassOptions() {
            var selectedType = $typeSelect.val(); // 'SYNTAX' or 'READING'
            var currentVal = $classSelect.val();  // 현재 선택된 값 저장
            
            // 3. 일단 화면의 목록을 싹 비웁니다. (가장 확실한 방법)
            $classSelect.empty();

            // 4. 백업해둔 옵션들 중에서 조건에 맞는 것만 다시 끼워넣습니다.
            $allOptions.each(function() {
                var $opt = $(this);
                var text = $opt.text();
                var val = $opt.val();

                // (1) "--------" (빈 값)은 무조건 표시
                if (!val) {
                    $classSelect.append($opt);
                    return; 
                }

                // (2) 필터링 로직
                if (selectedType === 'SYNTAX') {
                    // 구문 타입 -> 텍스트에 '구문'이 있는 것만 추가
                    if (text.indexOf('구문') !== -1) {
                        $classSelect.append($opt);
                    }
                } else if (selectedType === 'READING') {
                    // 독해 타입 -> 텍스트에 '독해'가 있는 것만 추가
                    if (text.indexOf('독해') !== -1) {
                        $classSelect.append($opt);
                    }
                } else {
                    // 타입 미선택 -> 모두 표시
                    $classSelect.append($opt);
                }
            });

            // 5. 필터링 후, 아까 선택했던 값이 유효하다면 다시 선택 유지
            $classSelect.val(currentVal);

            // 6. [충돌 방지] 요일 필터가 있다면 초기화 (꼬임 방지)
            var $dayFilter = $classSelect.prev('.day-filter-box');
            if ($dayFilter.length > 0) {
                $dayFilter.val(''); 
            }
        }

        // 이벤트 연결
        $typeSelect.on('change', updateExtraClassOptions);
        
        // 초기 실행
        updateExtraClassOptions();
    });
})(django.jQuery);