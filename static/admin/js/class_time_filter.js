/* static/admin/js/class_time_filter.js */

(function($) {
    $(document).ready(function() {
        console.log("🚀 시간표 필터 스크립트가 실행되었습니다!"); // F12 콘솔에서 확인 가능

        // 필터를 적용할 필드 이름의 '뒷부분' (ID가 바뀌어도 찾을 수 있게 함)
        const targetSuffixes = ['syntax_class', 'reading_class', 'extra_class'];

        targetSuffixes.forEach(function(suffix) {
            // "name" 속성이 해당 글자로 끝나는 모든 select 박스를 찾음
            const $selects = $('select[name$="-' + suffix + '"]');
            
            $selects.each(function() {
                const $select = $(this);
                
                // 이미 필터가 붙어있으면 패스 (중복 방지)
                if ($select.prev('.day-filter-box').length > 0) return;

                console.log("✅ 타겟 필드 발견:", $select.attr('id'));

                // 1. 요일 선택 박스 생성
                const $dayFilter = $('<select class="day-filter-box" style="margin-right:8px; padding:4px; border:1px solid #ccc; border-radius:4px; background:#fff;">')
                    .append('<option value="">📅 요일 선택 (전체)</option>')
                    .append('<option value="월요일">월요일</option>')
                    .append('<option value="화요일">화요일</option>')
                    .append('<option value="수요일">수요일</option>')
                    .append('<option value="목요일">목요일</option>')
                    .append('<option value="금요일">금요일</option>')
                    .append('<option value="토요일">토요일</option>')
                    .append('<option value="일요일">일요일</option>');

                // 2. 시간표 박스 앞에 삽입
                $select.before($dayFilter);

                // 3. 원본 옵션 복사
                const $options = $select.find('option').clone();

                // 4. 필터링 동작 연결
                $dayFilter.on('change', function() {
                    const selectedDay = $(this).val();
                    $select.empty(); // 비우기

                    $options.each(function() {
                        const text = $(this).text();
                        const value = $(this).val();
                        
                        // 값이 비었거나(--------), 선택한 요일이 포함되어 있으면 표시
                        if (value === "" || selectedDay === "" || text.indexOf(selectedDay) !== -1) {
                            $select.append($(this));
                        }
                    });
                    
                    // 필터링 후 첫 번째 옵션 선택 (사용자 편의)
                    $select.val($select.find('option:first').val());
                });
            });
        });
    });
})(django.jQuery);